-- D'Paniagua Technology: creación atómica de pedidos y descuento de inventario.
-- Ejecutar en Supabase > SQL Editor. Seguro para volver a ejecutar.
-- Solo se descuenta stock al registrar un pedido contra entrega.
-- PayPal/tarjeta requieren confirmación de pago del proveedor en servidor antes de descontar.

alter table public.orders
  add column if not exists payment_method text not null default 'cash_on_delivery'
  check (payment_method in ('paypal','card','cash_on_delivery','whatsapp'));

create or replace function public.create_order_and_decrease_stock(
  p_items jsonb,
  p_payment_method text default 'cash_on_delivery'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_order_id uuid;
  v_total numeric(12,2);
  v_item record;
  v_product public.products%rowtype;
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesión para realizar el pedido.' using errcode = '28000';
  end if;

  if p_payment_method <> 'cash_on_delivery' then
    raise exception 'Este método requiere confirmación de pago en servidor.' using errcode = '22023';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'El carrito está vacío.' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer)
    where x.product_id is null or x.quantity is null or x.quantity < 1
  ) then
    raise exception 'El carrito contiene artículos o cantidades no válidas.' using errcode = '22023';
  end if;

  if (select count(*) from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer))
     <> (select count(distinct x.product_id) from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer)) then
    raise exception 'Hay productos repetidos en el carrito.' using errcode = '22023';
  end if;

  -- Bloquea los productos en orden estable para evitar ventas simultáneas por encima del stock.
  for v_item in
    select x.product_id, x.quantity
    from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer)
    order by x.product_id
  loop
    select * into v_product
    from public.products
    where id = v_item.product_id
    for update;

    if not found or not v_product.is_published then
      raise exception 'Uno de los productos ya no está disponible.' using errcode = 'P0001';
    end if;

    if v_product.stock < v_item.quantity then
      raise exception 'Stock insuficiente para "%". Disponibles: %, solicitados: %.',
        v_product.name, v_product.stock, v_item.quantity
        using errcode = 'P0001';
    end if;
  end loop;

  select sum(p.price * x.quantity)::numeric(12,2)
  into v_total
  from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer)
  join public.products p on p.id = x.product_id
  where p.is_published;

  if v_total is null then
    raise exception 'No se pudo calcular el total del pedido.' using errcode = '22023';
  end if;

  insert into public.orders(user_id,total,status,payment_method)
  values(v_user_id,v_total,'pending','cash_on_delivery')
  returning id into v_order_id;

  insert into public.order_items(order_id,product_id,quantity,unit_price)
  select v_order_id,p.id,x.quantity,p.price
  from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer)
  join public.products p on p.id=x.product_id;

  update public.products p
  set stock = p.stock - x.quantity,
      updated_at = now()
  from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer)
  where p.id=x.product_id;

  return v_order_id;
end;
$$;

revoke all on function public.create_order_and_decrease_stock(jsonb,text) from public;
revoke all on function public.create_order_and_decrease_stock(jsonb,text) from anon;
grant execute on function public.create_order_and_decrease_stock(jsonb,text) to authenticated;

comment on function public.create_order_and_decrease_stock(jsonb,text) is
'Creates a cash-on-delivery order, validates and locks products, inserts order items, and decreases stock atomically.';
