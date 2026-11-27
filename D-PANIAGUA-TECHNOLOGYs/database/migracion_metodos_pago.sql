-- Ejecutar una sola vez en Supabase SQL Editor.
-- Guarda la modalidad elegida; no procesa cobros de tarjeta ni confirma pagos PayPal.
alter table public.orders
  add column if not exists payment_method text not null default 'cash_on_delivery'
  check (payment_method in ('paypal','card','cash_on_delivery','whatsapp'));

comment on column public.orders.payment_method is
  'Método elegido por el cliente. El procesamiento real de PayPal/tarjeta requiere pasarela y verificación en servidor.';
