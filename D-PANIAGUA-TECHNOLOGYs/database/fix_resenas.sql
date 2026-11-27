-- D'Paniagua Technology: publicar reseñas de productos inmediatamente.
-- Ejecutar una sola vez en Supabase > SQL Editor. Se puede volver a ejecutar.
alter table public.reviews
  add column if not exists product_id uuid references public.products(id) on delete cascade;

create index if not exists reviews_product_visible_idx
  on public.reviews(product_id, is_visible, created_at desc);

create unique index if not exists reviews_one_per_user_product_uidx
  on public.reviews(user_id, product_id)
  where product_id is not null;

alter table public.reviews enable row level security;

drop policy if exists "visible reviews public read" on public.reviews;
drop policy if exists "customer create own review" on public.reviews;
drop policy if exists "customer update own pending review" on public.reviews;
drop policy if exists "admin review moderation" on public.reviews;

create policy "visible reviews public read"
  on public.reviews for select to anon, authenticated
  using (is_visible or user_id = auth.uid() or public.is_admin());

-- Solo usuarios con sesión pueden publicar; no se permite suplantar otro usuario.
-- is_verified sigue siendo false: publicar automáticamente NO significa compra verificada.
create policy "customer create own review"
  on public.reviews for insert to authenticated
  with check (
    user_id = auth.uid()
    and is_visible = true
    and is_verified = false
  );

create policy "admin review moderation"
  on public.reviews for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());
