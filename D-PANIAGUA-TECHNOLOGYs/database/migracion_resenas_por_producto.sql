-- Ejecutar si ya habías instalado el esquema anterior. Seguro para volver a ejecutar.
alter table public.reviews add column if not exists product_id uuid references public.products(id) on delete cascade;
create index if not exists reviews_product_visible_idx on public.reviews(product_id,is_visible,created_at desc);
create unique index if not exists reviews_one_per_user_product_uidx on public.reviews(user_id,product_id) where product_id is not null;
