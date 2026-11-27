-- D'Paniagua Technology: combos, entrega, pagos y administracion transaccional.
-- Ejecutar despues de schema.sql y migracion_metodos_pago.sql. Es re-ejecutable.

alter table public.profiles add column if not exists phone text;
alter table public.profiles add column if not exists is_active boolean not null default true;
revoke insert,update,delete on public.profiles from anon,authenticated;
grant update(full_name) on public.profiles to authenticated;
alter table public.products add column if not exists image_urls text[] not null default '{}';
alter table public.products add column if not exists offer_label text;
alter table public.products add column if not exists status text not null default 'active';
alter table public.products drop constraint if exists products_status_check;
alter table public.products add constraint products_status_check check (status in ('active','inactive','archived'));
alter table public.orders add column if not exists delivery_address jsonb not null default '{}'::jsonb;
alter table public.orders add column if not exists subtotal numeric(12,2) not null default 0;
alter table public.orders add column if not exists shipping_cost numeric(12,2) not null default 0;
alter table public.orders add column if not exists discount_amount numeric(12,2) not null default 0;
update public.orders set subtotal=total where subtotal=0 and total>0;
alter table public.orders add column if not exists payment_status text not null default 'pending';
alter table public.orders add column if not exists inventory_released boolean not null default true;
alter table public.orders drop constraint if exists orders_payment_status_check;
alter table public.orders add constraint orders_payment_status_check
  check (payment_status in ('pending','confirmed','rejected','refunded'));
alter table public.orders add column if not exists payment_method text not null default 'cash_on_delivery';
alter table public.orders drop constraint if exists orders_payment_method_check;
alter table public.orders add constraint orders_payment_method_check check(payment_method in ('paypal','card','cash_on_delivery','whatsapp'));

create table if not exists public.bundles (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 160),
  description text not null default '',
  category text not null,
  image_url text,
  price numeric(12,2) not null check (price >= 0),
  stock integer not null default 0 check (stock >= 0),
  starts_at timestamptz,
  ends_at timestamptz,
  status text not null default 'inactive' check (status in ('active','inactive','sold_out')),
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);
create table if not exists public.bundle_items (
  id uuid primary key default gen_random_uuid(),
  bundle_id uuid not null references public.bundles(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  unique(bundle_id, product_id)
);
create index if not exists bundle_items_product_idx on public.bundle_items(product_id);
create index if not exists bundles_public_idx on public.bundles(is_published,status,starts_at,ends_at);

alter table public.order_items alter column product_id drop not null;
alter table public.order_items add column if not exists bundle_id uuid references public.bundles(id) on delete restrict;
alter table public.order_items add column if not exists components jsonb not null default '[]'::jsonb;
alter table public.order_items add column if not exists list_price numeric(12,2) not null default 0;
update public.order_items set list_price=unit_price where list_price=0 and unit_price>0;
alter table public.order_items drop constraint if exists order_items_order_id_product_id_key;
create unique index if not exists order_items_order_product_uidx
  on public.order_items(order_id,product_id) where product_id is not null;
create unique index if not exists order_items_order_bundle_uidx
  on public.order_items(order_id,bundle_id) where bundle_id is not null;
alter table public.order_items drop constraint if exists order_items_one_kind_check;
alter table public.order_items add constraint order_items_one_kind_check
  check ((product_id is not null) <> (bundle_id is not null));

create table if not exists public.order_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  changed_by uuid references public.profiles(id) on delete set null,
  change_type text not null,
  changes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists order_history_order_idx on public.order_history(order_id,created_at desc);
create table if not exists public.inventory_history (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products(id) on delete set null,
  changed_by uuid references public.profiles(id) on delete set null,
  old_stock integer not null,
  new_stock integer not null,
  created_at timestamptz not null default now()
);
create index if not exists inventory_history_created_idx on public.inventory_history(created_at desc);
alter table public.inventory_history enable row level security;
grant select on public.inventory_history,public.order_history to authenticated;
drop policy if exists "inventory history admin read" on public.inventory_history;
create policy "inventory history admin read" on public.inventory_history for select to authenticated using(public.is_admin());
revoke insert,update,delete on public.inventory_history from anon,authenticated;
revoke insert,update,delete on public.order_history from anon,authenticated;

create or replace function public.log_product_stock_change()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  if new.stock is distinct from old.stock then
    insert into public.inventory_history(product_id,changed_by,old_stock,new_stock)
      values(new.id,auth.uid(),old.stock,new.stock);
  end if;
  return new;
end;
$$;
drop trigger if exists products_stock_history on public.products;
create trigger products_stock_history after update of stock on public.products
for each row execute function public.log_product_stock_change();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='admin' and is_active=true); $$;
create or replace function public.is_active_user()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles where id=auth.uid() and is_active=true); $$;
revoke all on function public.is_active_user() from public;
grant execute on function public.is_active_user() to anon,authenticated;
drop policy if exists "orders own read" on public.orders;
create policy "orders own read" on public.orders for select to authenticated using((user_id=auth.uid() and public.is_active_user()) or public.is_admin());
drop policy if exists "items own read" on public.order_items;
create policy "items own read" on public.order_items for select to authenticated
  using(exists(select 1 from public.orders o where o.id=order_id and ((o.user_id=auth.uid() and public.is_active_user()) or public.is_admin())));
drop policy if exists "customer create own review" on public.reviews;
create policy "customer create own review" on public.reviews for insert to authenticated
  with check(user_id=auth.uid() and public.is_active_user() and is_visible=true and is_verified=false);

alter table public.bundles enable row level security;
alter table public.bundle_items enable row level security;
alter table public.order_history enable row level security;
grant select on public.bundles,public.bundle_items to anon,authenticated;
revoke insert,update,delete on public.bundles,public.bundle_items from anon,authenticated;
drop policy if exists "bundles public read" on public.bundles;
create policy "bundles public read" on public.bundles for select to anon,authenticated
  using (is_published and status='active' and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now()) or public.is_admin());
drop policy if exists "bundles admin manage" on public.bundles;
create policy "bundles admin manage" on public.bundles for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "published products public read" on public.products;
create policy "published products public read" on public.products for select to anon,authenticated using((is_published and status='active') or public.is_admin());
drop policy if exists "bundle items public read" on public.bundle_items;
create policy "bundle items public read" on public.bundle_items for select to anon,authenticated
  using (exists(select 1 from public.bundles b where b.id=bundle_id and b.is_published and b.status='active'
    and (b.starts_at is null or b.starts_at <= now()) and (b.ends_at is null or b.ends_at > now())) or public.is_admin());
drop policy if exists "bundle items admin manage" on public.bundle_items;
create policy "bundle items admin manage" on public.bundle_items for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "order history admin read" on public.order_history;
create policy "order history admin read" on public.order_history for select to authenticated using(public.is_admin());

-- Quita escrituras directas de pedidos y líneas: creación/edición pasa por RPCs.
drop policy if exists "orders own create" on public.orders;
drop policy if exists "orders admin update" on public.orders;
drop policy if exists "orders admin delete" on public.orders;
drop policy if exists "items own create" on public.order_items;
drop policy if exists "items admin manage" on public.order_items;
revoke insert, update, delete on public.orders from anon, authenticated;
revoke insert, update, delete on public.order_items from anon, authenticated;
do $$ begin
  if to_regprocedure('public.create_order_and_decrease_stock(jsonb,text)') is not null then
    execute 'revoke all on function public.create_order_and_decrease_stock(jsonb,text) from public,anon,authenticated';
  end if;
end $$;

create or replace function public.order_line_requirements(p_lines jsonb)
returns table(product_id uuid, quantity integer)
language sql stable security definer set search_path=public
as $$
  with lines as (
    select x.product_id,x.bundle_id,x.quantity
    from jsonb_to_recordset(coalesce(p_lines,'[]'::jsonb)) as x(product_id uuid,bundle_id uuid,quantity integer)
  ), expanded as (
    select l.product_id,l.quantity from lines l where l.product_id is not null
    union all
    select bi.product_id,(l.quantity*bi.quantity)::integer
    from lines l join public.bundle_items bi on bi.bundle_id=l.bundle_id
  )
  select e.product_id,sum(e.quantity)::integer from expanded e group by e.product_id
$$;
revoke all on function public.order_line_requirements(jsonb) from public,anon,authenticated;

create or replace function public.create_order_with_inventory(p_lines jsonb,p_delivery_address jsonb)
returns uuid language plpgsql security definer set search_path=public
as $$
declare
  v_user_id uuid := auth.uid(); v_order_id uuid; v_total numeric(12,2); v_subtotal numeric(12,2); v_pid uuid; v_product public.products%rowtype;
  v_line record; v_addr jsonb := coalesce(p_delivery_address,'{}'::jsonb);
begin
  if v_user_id is null then raise exception 'Debes iniciar sesión para realizar el pedido.' using errcode='28000'; end if;
  if not public.is_active_user() then raise exception 'La cuenta no está activa para realizar pedidos.' using errcode='42501'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'El carrito está vacío.' using errcode='22023'; end if;
  if jsonb_typeof(v_addr)<>'object' or exists(select 1 from unnest(array['full_name','phone','email','province','municipality','sector','street','house_number','reference']) k where length(trim(coalesce(v_addr->>k,'')))=0) then
    raise exception 'Completa nombre, teléfono, correo y dirección de entrega.' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_to_recordset(p_lines) x(product_id uuid,bundle_id uuid,quantity integer)
      where (x.product_id is null)=(x.bundle_id is null) or x.quantity is null or x.quantity<1) then
    raise exception 'El carrito contiene artículos o cantidades no válidas.' using errcode='22023';
  end if;
  if (select count(*) from jsonb_to_recordset(p_lines) x(product_id uuid,bundle_id uuid,quantity integer)) <>
     (select count(distinct (coalesce(x.product_id,x.bundle_id),x.bundle_id is not null)) from jsonb_to_recordset(p_lines) x(product_id uuid,bundle_id uuid,quantity integer)) then
    raise exception 'Hay líneas repetidas en el carrito.' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_to_recordset(p_lines) x(product_id uuid,bundle_id uuid,quantity integer)
      where x.bundle_id is not null and not exists(select 1 from public.bundle_items bi where bi.bundle_id=x.bundle_id)) then
    raise exception 'Cada combo debe incluir al menos un producto.' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_to_recordset(p_lines) x(product_id uuid,bundle_id uuid,quantity integer)
      where x.product_id is not null and not exists(select 1 from public.products p where p.id=x.product_id and p.is_published)) or
     exists(select 1 from jsonb_to_recordset(p_lines) x(product_id uuid,bundle_id uuid,quantity integer)
      where x.bundle_id is not null and not exists(select 1 from public.bundles b where b.id=x.bundle_id and b.is_published and b.status='active'
        and b.stock>=x.quantity and (b.starts_at is null or b.starts_at<=now()) and (b.ends_at is null or b.ends_at>now()))) then
    raise exception 'Un producto o combo ya no está disponible.' using errcode='P0001';
  end if;
  -- El mismo orden de bloqueo se usa en checkout y edición: combos, después productos.
  for v_pid in select x.bundle_id from jsonb_to_recordset(p_lines) x(product_id uuid,bundle_id uuid,quantity integer)
      where x.bundle_id is not null order by x.bundle_id loop
    perform 1 from public.bundles where id=v_pid for update;
    if not found then raise exception 'No se encontró un combo del pedido.' using errcode='P0002'; end if;
  end loop;
  if exists(select 1 from jsonb_to_recordset(p_lines) x(product_id uuid,bundle_id uuid,quantity integer)
      join public.bundles b on b.id=x.bundle_id
      where b.stock<x.quantity or not b.is_published or b.status<>'active'
        or (b.starts_at is not null and b.starts_at>now()) or (b.ends_at is not null and b.ends_at<=now())) then
    raise exception 'No hay suficientes combos disponibles.' using errcode='P0001';
  end if;
  for v_pid in select r.product_id from public.order_line_requirements(p_lines) r order by r.product_id loop
    select * into v_product from public.products where id=v_pid for update;
    if not found or not v_product.is_published or v_product.status<>'active' then
      raise exception 'Un producto incluido ya no está disponible.' using errcode='P0001';
    end if;
    if v_product.stock < (select r.quantity from public.order_line_requirements(p_lines) r where r.product_id=v_pid) then
      raise exception 'Existencias insuficientes para "%".',v_product.name using errcode='P0001';
    end if;
  end loop;
  select sum(case when x.product_id is not null then p.price else b.price end*x.quantity)::numeric(12,2)
    into v_total from jsonb_to_recordset(p_lines) x(product_id uuid,bundle_id uuid,quantity integer)
    left join public.products p on p.id=x.product_id left join public.bundles b on b.id=x.bundle_id;
  if v_total is null then raise exception 'No se pudo calcular el total.' using errcode='22023'; end if;
  select sum(case when x.product_id is not null then coalesce(p.compare_at_price,p.price) else bi.list_price end*x.quantity)::numeric(12,2)
    into v_subtotal from jsonb_to_recordset(p_lines) x(product_id uuid,bundle_id uuid,quantity integer)
    left join public.products p on p.id=x.product_id left join public.bundles b on b.id=x.bundle_id
    left join lateral (select sum(p2.price*bi2.quantity)::numeric(12,2) list_price from public.bundle_items bi2
      join public.products p2 on p2.id=bi2.product_id where bi2.bundle_id=b.id) bi on true;
  insert into public.orders(user_id,total,subtotal,discount_amount,shipping_cost,status,payment_method,payment_status,delivery_address,inventory_released)
    values(v_user_id,v_total,v_subtotal,greatest(v_subtotal-v_total,0),0,'pending','cash_on_delivery','pending',v_addr,false) returning id into v_order_id;
  for v_line in select x.* from jsonb_to_recordset(p_lines) x(product_id uuid,bundle_id uuid,quantity integer) loop
    if v_line.product_id is not null then
      insert into public.order_items(order_id,product_id,quantity,unit_price,list_price,components)
        select v_order_id,p.id,v_line.quantity,p.price,coalesce(p.compare_at_price,p.price),jsonb_build_array(jsonb_build_object('product_id',p.id,'quantity',1))
        from public.products p where p.id=v_line.product_id;
    else
      insert into public.order_items(order_id,bundle_id,quantity,unit_price,list_price,components)
        select v_order_id,b.id,v_line.quantity,b.price,
          (select sum(p.price*bi.quantity)::numeric(12,2) from public.bundle_items bi join public.products p on p.id=bi.product_id where bi.bundle_id=b.id),
          (select jsonb_agg(jsonb_build_object('product_id',bi.product_id,'quantity',bi.quantity)) from public.bundle_items bi where bi.bundle_id=b.id)
        from public.bundles b where b.id=v_line.bundle_id;
    end if;
  end loop;
  update public.products p set stock=p.stock-r.quantity,updated_at=now()
    from public.order_line_requirements(p_lines) r where p.id=r.product_id;
  update public.bundles b set stock=b.stock-x.quantity,updated_at=now()
    from jsonb_to_recordset(p_lines) x(product_id uuid,bundle_id uuid,quantity integer) where b.id=x.bundle_id;
  insert into public.order_history(order_id,changed_by,change_type,changes)
    values(v_order_id,v_user_id,'created',jsonb_build_object('status','pending','total',v_total));
  return v_order_id;
end;
$$;
revoke all on function public.create_order_with_inventory(jsonb,jsonb) from public,anon;
grant execute on function public.create_order_with_inventory(jsonb,jsonb) to authenticated;

create or replace function public.admin_update_order(
  p_order_id uuid,p_status text default null,p_delivery_address jsonb default null,
  p_payment_method text default null,p_payment_status text default null,p_items jsonb default null
) returns void language plpgsql security definer set search_path=public
as $$
declare
  v_old public.orders%rowtype; v_new_status text; v_new_method text; v_new_payment text;
  v_old_demand jsonb := '{}'::jsonb; v_pid uuid; v_old_qty integer; v_new_qty integer; v_stock integer;
  v_total numeric(12,2); v_subtotal numeric(12,2); v_line record; v_changes jsonb := '{}'::jsonb;
begin
  if not public.is_admin() then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  select * into v_old from public.orders where id=p_order_id for update;
  if not found then raise exception 'No se encontró el pedido.' using errcode='P0002'; end if;
  v_new_status:=coalesce(p_status,v_old.status); v_new_method:=coalesce(p_payment_method,v_old.payment_method);
  v_new_payment:=coalesce(p_payment_status,v_old.payment_status);
  if v_new_status not in ('pending','confirmed','processing','shipped','completed','cancelled') then raise exception 'Estado de pedido inválido.' using errcode='22023'; end if;
  if v_new_method not in ('paypal','card','cash_on_delivery','whatsapp') or v_new_payment not in ('pending','confirmed','rejected','refunded') then raise exception 'Estado de pago inválido.' using errcode='22023'; end if;
  if v_old.status='cancelled' and v_new_status<>'cancelled' then raise exception 'Un pedido cancelado no se puede reactivar.' using errcode='22023'; end if;
  if v_new_status='cancelled' and v_old.status<>'cancelled' and v_new_payment='confirmed' then raise exception 'Registra el reembolso o rechazo del pago antes de cancelar.' using errcode='22023'; end if;
  if v_new_method<>v_old.payment_method and (v_old.status<>'pending' or v_old.payment_status<>'pending') then raise exception 'El método de pago solo se cambia mientras el pedido y el pago estén pendientes.' using errcode='22023'; end if;
  if p_delivery_address is not null and (jsonb_typeof(p_delivery_address)<>'object' or length(trim(coalesce(p_delivery_address->>'full_name','')))<2) then raise exception 'Dirección de entrega no válida.' using errcode='22023'; end if;
  if p_items is not null and (v_old.status<>'pending' or v_old.inventory_released) then raise exception 'Los artículos solo se pueden editar mientras el pedido pendiente mantiene sus existencias reservadas.' using errcode='22023'; end if;
  if p_items is not null then
    if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 or exists(
      select 1 from jsonb_to_recordset(p_items) x(product_id uuid,bundle_id uuid,quantity integer)
      where (x.product_id is null)=(x.bundle_id is null) or x.quantity is null or x.quantity<1) then raise exception 'Lista de productos no válida.' using errcode='22023'; end if;
    if exists(select 1 from jsonb_to_recordset(p_items) x(product_id uuid,bundle_id uuid,quantity integer)
      where x.product_id is not null and not exists(select 1 from public.products p where p.id=x.product_id and p.is_published and p.status='active')) or
       exists(select 1 from jsonb_to_recordset(p_items) x(product_id uuid,bundle_id uuid,quantity integer)
      where x.bundle_id is not null and not exists(select 1 from public.bundles b where b.id=x.bundle_id and b.is_published and b.status='active'
        and (b.starts_at is null or b.starts_at<=now()) and (b.ends_at is null or b.ends_at>now()))) then
      raise exception 'Uno de los productos o combos no se puede vender.' using errcode='P0001'; end if;
    if exists(select 1 from jsonb_to_recordset(p_items) x(product_id uuid,bundle_id uuid,quantity integer)
      where x.bundle_id is not null and not exists(select 1 from public.bundle_items bi where bi.bundle_id=x.bundle_id)) then
      raise exception 'Cada combo debe incluir al menos un producto.' using errcode='22023'; end if;
    -- Restituye o reserva la cantidad de combos con el mismo bloqueo transaccional.
    for v_line in
      select x.id from (select oi.bundle_id id from public.order_items oi where oi.order_id=p_order_id and oi.bundle_id is not null
        union select z.bundle_id from jsonb_to_recordset(p_items) z(product_id uuid,bundle_id uuid,quantity integer) where z.bundle_id is not null) x order by x.id
    loop
      perform 1 from public.bundles where id=v_line.id for update;
      if not found then raise exception 'No se encontró un combo del pedido.' using errcode='P0002'; end if;
    end loop;
    for v_line in
      select x.id,coalesce(oldq.quantity,0) old_quantity,coalesce(newq.quantity,0) new_quantity
      from (select oi.bundle_id id from public.order_items oi where oi.order_id=p_order_id and oi.bundle_id is not null
        union select z.bundle_id from jsonb_to_recordset(p_items) z(product_id uuid,bundle_id uuid,quantity integer) where z.bundle_id is not null) x
      left join (select bundle_id,sum(quantity)::integer quantity from public.order_items where order_id=p_order_id and bundle_id is not null group by bundle_id) oldq on oldq.bundle_id=x.id
      left join (select z.bundle_id,sum(z.quantity)::integer quantity from jsonb_to_recordset(p_items) z(product_id uuid,bundle_id uuid,quantity integer) where z.bundle_id is not null group by z.bundle_id) newq on newq.bundle_id=x.id
    loop
      select stock into v_stock from public.bundles where id=v_line.id;
      if v_stock+v_line.old_quantity<v_line.new_quantity then raise exception 'Existencias insuficientes para un combo.' using errcode='P0001'; end if;
      update public.bundles set stock=v_stock+v_line.old_quantity-v_line.new_quantity,updated_at=now() where id=v_line.id;
    end loop;
    select coalesce(jsonb_object_agg(q.product_id::text,q.quantity),'{}'::jsonb) into v_old_demand from (
      select c.product_id,sum(c.quantity*oi.quantity)::integer quantity from public.order_items oi
      cross join lateral jsonb_to_recordset(oi.components) c(product_id uuid,quantity integer)
      where oi.order_id=p_order_id group by c.product_id) q;
    for v_pid in
      select x.id from (select key::uuid id from jsonb_each(v_old_demand)
        union select r.product_id from public.order_line_requirements(p_items) r) x order by x.id
    loop
      select stock into v_stock from public.products where id=v_pid for update;
      if not found then raise exception 'No se encontró un producto del pedido.' using errcode='P0002'; end if;
    end loop;
    for v_pid in select r.product_id from public.order_line_requirements(p_items) r order by r.product_id loop
      select stock into v_stock from public.products where id=v_pid;
      v_old_qty:=coalesce((v_old_demand->>v_pid::text)::integer,0);
      select r.quantity into v_new_qty from public.order_line_requirements(p_items) r where r.product_id=v_pid;
      if not exists(select 1 from public.products where id=v_pid and is_published and status='active') or v_stock+v_old_qty<v_new_qty then
        raise exception 'Existencias insuficientes o producto no disponible.' using errcode='P0001';
      end if;
    end loop;
    for v_pid in select x.id from (select key::uuid id from jsonb_each(v_old_demand)
        union select r.product_id from public.order_line_requirements(p_items) r) x order by x.id loop
      select stock into v_stock from public.products where id=v_pid;
      v_old_qty:=coalesce((v_old_demand->>v_pid::text)::integer,0);
      select coalesce((select quantity from public.order_line_requirements(p_items) where product_id=v_pid),0) into v_new_qty;
      update public.products set stock=v_stock+v_old_qty-coalesce(v_new_qty,0),updated_at=now() where id=v_pid;
    end loop;
    delete from public.order_items where order_id=p_order_id;
    for v_line in select x.* from jsonb_to_recordset(p_items) x(product_id uuid,bundle_id uuid,quantity integer) loop
      if v_line.product_id is not null then
        insert into public.order_items(order_id,product_id,quantity,unit_price,list_price,components)
          select p_order_id,p.id,v_line.quantity,p.price,coalesce(p.compare_at_price,p.price),jsonb_build_array(jsonb_build_object('product_id',p.id,'quantity',1)) from public.products p where p.id=v_line.product_id;
      else
        insert into public.order_items(order_id,bundle_id,quantity,unit_price,list_price,components)
          select p_order_id,b.id,v_line.quantity,b.price,
            (select sum(p.price*bi.quantity)::numeric(12,2) from public.bundle_items bi join public.products p on p.id=bi.product_id where bi.bundle_id=b.id),
            (select jsonb_agg(jsonb_build_object('product_id',bi.product_id,'quantity',bi.quantity)) from public.bundle_items bi where bi.bundle_id=b.id)
          from public.bundles b where b.id=v_line.bundle_id;
      end if;
    end loop;
    select sum(unit_price*quantity)::numeric(12,2),sum(list_price*quantity)::numeric(12,2) into v_total,v_subtotal from public.order_items where order_id=p_order_id;
    v_changes:=v_changes||jsonb_build_object('items',true,'total',jsonb_build_object('from',v_old.total,'to',v_total));
  else v_total:=v_old.total; v_subtotal:=v_old.subtotal; end if;
  if v_new_status='cancelled' and v_old.status<>'cancelled' and not v_old.inventory_released then
    -- Bloquea combos primero y productos después, igual que el checkout.
    for v_pid in select bundle_id from public.order_items where order_id=p_order_id and bundle_id is not null order by bundle_id loop
      perform 1 from public.bundles where id=v_pid for update;
    end loop;
    for v_line in select c.product_id,sum(c.quantity*oi.quantity)::integer quantity from public.order_items oi
      cross join lateral jsonb_to_recordset(oi.components) c(product_id uuid,quantity integer)
      where oi.order_id=p_order_id group by c.product_id order by c.product_id loop
      update public.products set stock=stock+v_line.quantity,updated_at=now() where id=v_line.product_id;
    end loop;
    update public.bundles b set stock=b.stock+q.quantity,updated_at=now() from (
      select bundle_id,sum(quantity)::integer quantity from public.order_items where order_id=p_order_id and bundle_id is not null group by bundle_id
    ) q where b.id=q.bundle_id;
    update public.orders set inventory_released=true where id=p_order_id;
  end if;
  if v_new_status<>v_old.status then v_changes:=v_changes||jsonb_build_object('status',jsonb_build_object('from',v_old.status,'to',v_new_status)); end if;
  if v_new_method<>v_old.payment_method then v_changes:=v_changes||jsonb_build_object('payment_method',jsonb_build_object('from',v_old.payment_method,'to',v_new_method)); end if;
  if v_new_payment<>v_old.payment_status then v_changes:=v_changes||jsonb_build_object('payment_status',jsonb_build_object('from',v_old.payment_status,'to',v_new_payment)); end if;
  if p_delivery_address is not null and p_delivery_address<>v_old.delivery_address then v_changes:=v_changes||jsonb_build_object('delivery_address','actualizada'); end if;
  update public.orders set status=v_new_status,payment_method=v_new_method,payment_status=v_new_payment,
    delivery_address=coalesce(p_delivery_address,delivery_address),total=v_total,subtotal=v_subtotal,
    discount_amount=greatest(v_subtotal-v_total,0),updated_at=now() where id=p_order_id;
  if v_changes<>'{}'::jsonb then
    insert into public.order_history(order_id,changed_by,change_type,changes) values(p_order_id,auth.uid(),'admin_update',v_changes);
  end if;
end;
$$;
revoke all on function public.admin_update_order(uuid,text,jsonb,text,text,jsonb) from public,anon;
grant execute on function public.admin_update_order(uuid,text,jsonb,text,text,jsonb) to authenticated;

create or replace function public.admin_save_bundle(p_bundle jsonb,p_items jsonb)
returns uuid language plpgsql security definer set search_path=public
as $$
declare
  v_id uuid; v_line record; v_start timestamptz; v_end timestamptz;
begin
  if not public.is_admin() then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  if p_bundle is null or jsonb_typeof(p_bundle)<>'object' or p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then
    raise exception 'Completa el combo y agrega al menos un producto.' using errcode='22023'; end if;
  if length(trim(coalesce(p_bundle->>'name','')))<2 or length(trim(coalesce(p_bundle->>'category','')))<2 or
     coalesce((p_bundle->>'price')::numeric,-1)<0 or coalesce((p_bundle->>'stock')::integer,-1)<0 or
     coalesce(p_bundle->>'status','inactive') not in ('active','inactive','sold_out') then
    raise exception 'Nombre, categoría, precio, cantidad o estado no válidos.' using errcode='22023'; end if;
  if exists(select 1 from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer) where x.product_id is null or x.quantity is null or x.quantity<1) or
     (select count(*) from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer)) <>
     (select count(distinct x.product_id) from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer)) then
    raise exception 'Los productos incluidos deben ser válidos y no repetirse.' using errcode='22023'; end if;
  if exists(select 1 from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer)
    where not exists(select 1 from public.products p where p.id=x.product_id)) then raise exception 'No se encontró un producto incluido.' using errcode='P0002'; end if;
  v_start:=nullif(p_bundle->>'starts_at','')::timestamptz; v_end:=nullif(p_bundle->>'ends_at','')::timestamptz;
  if v_start is not null and v_end is not null and v_end<=v_start then raise exception 'La fecha final debe ser posterior a la inicial.' using errcode='22023'; end if;
  if coalesce(p_bundle->>'id','')<>'' then
    v_id:=(p_bundle->>'id')::uuid;
    perform 1 from public.bundles where id=v_id for update;
    if not found then raise exception 'No se encontró el combo.' using errcode='P0002'; end if;
    update public.bundles set name=trim(p_bundle->>'name'),description=coalesce(p_bundle->>'description',''),
      category=trim(p_bundle->>'category'),image_url=nullif(p_bundle->>'image_url',''),price=(p_bundle->>'price')::numeric,
      stock=(p_bundle->>'stock')::integer,starts_at=v_start,ends_at=v_end,status=p_bundle->>'status',
      is_published=coalesce((p_bundle->>'is_published')::boolean,false),updated_at=now() where id=v_id;
    delete from public.bundle_items where bundle_id=v_id;
  else
    insert into public.bundles(name,description,category,image_url,price,stock,starts_at,ends_at,status,is_published)
      values(trim(p_bundle->>'name'),coalesce(p_bundle->>'description',''),trim(p_bundle->>'category'),nullif(p_bundle->>'image_url',''),
        (p_bundle->>'price')::numeric,(p_bundle->>'stock')::integer,v_start,v_end,p_bundle->>'status',coalesce((p_bundle->>'is_published')::boolean,false)) returning id into v_id;
  end if;
  if coalesce((p_bundle->>'is_published')::boolean,false) and (p_bundle->>'status')='active' and
    (p_bundle->>'price')::numeric >= (select sum(p.price*x.quantity) from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer)
      join public.products p on p.id=x.product_id) then
    raise exception 'El precio especial debe ser menor que el precio individual total para publicar el combo.' using errcode='22023';
  end if;
  if coalesce((p_bundle->>'is_published')::boolean,false) and (p_bundle->>'status')='active' and exists(
    select 1 from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer)
    join public.products p on p.id=x.product_id where not p.is_published or p.status<>'active'
  ) then
    raise exception 'Para publicar el combo, todos sus productos deben estar publicados y activos.' using errcode='22023';
  end if;
  for v_line in select x.* from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer) loop
    insert into public.bundle_items(bundle_id,product_id,quantity) values(v_id,v_line.product_id,v_line.quantity);
  end loop;
  return v_id;
end;
$$;
revoke all on function public.admin_save_bundle(jsonb,jsonb) from public,anon;
grant execute on function public.admin_save_bundle(jsonb,jsonb) to authenticated;

create or replace function public.admin_delete_bundle(p_bundle_id uuid)
returns void language plpgsql security definer set search_path=public
as $$
begin
  if not public.is_admin() then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  delete from public.bundles where id=p_bundle_id;
  if not found then raise exception 'No se encontró el combo.' using errcode='P0002'; end if;
exception
  when foreign_key_violation then
    raise exception 'El combo ya aparece en pedidos. Desactívalo para conservar el historial.' using errcode='23503';
end;
$$;
revoke all on function public.admin_delete_bundle(uuid) from public,anon;
grant execute on function public.admin_delete_bundle(uuid) to authenticated;

comment on table public.bundles is 'Combos publicados; la disponibilidad de sus productos se valida y reserva en el checkout transaccional.';
comment on column public.orders.inventory_released is 'Indica si el inventario reservado por el checkout ya fue devuelto. Pedidos antiguos se conservan sin reponer automáticamente.';
