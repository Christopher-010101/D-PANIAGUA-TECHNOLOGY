-- Habilitar RLS en TODAS las tablas
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.reviews enable row level security;
alter table public.contact_messages enable row level security;

-- Profiles
create policy "profiles select own or admin" on public.profiles for select to authenticated
using (id=auth.uid() or public.is_admin());
create policy "profiles update own or admin" on public.profiles for update to authenticated
using (id=auth.uid() or public.is_admin()) with check (id=auth.uid() or public.is_admin());
-- No client policy can assign admin: role column changes must be made in trusted SQL editor.
revoke insert, delete, update on public.profiles from authenticated;
-- Los clientes pueden modificar únicamente su nombre visible; nunca el campo role.
grant update(full_name) on public.profiles to authenticated;

-- Categories and products: public catalog is read-only for anonymous/customer.
create policy "categories public read" on public.categories for select to anon,authenticated using (true);
create policy "categories admin manage" on public.categories for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "published products public read" on public.products for select to anon,authenticated using(is_published or public.is_admin());
create policy "products admin manage" on public.products for all to authenticated using(public.is_admin()) with check(public.is_admin());

-- Orders and items: users can read their own records; only admin can update order status.
create policy "orders own read" on public.orders for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy "orders own create" on public.orders for insert to authenticated with check(user_id=auth.uid());
create policy "orders admin update" on public.orders for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "orders admin delete" on public.orders for delete to authenticated using(public.is_admin());
create policy "items own read" on public.order_items for select to authenticated
using(exists(select 1 from public.orders o where o.id=order_id and (o.user_id=auth.uid() or public.is_admin())));
create policy "items own create" on public.order_items for insert to authenticated
with check(exists(select 1 from public.orders o where o.id=order_id and o.user_id=auth.uid()));
create policy "items admin manage" on public.order_items for all to authenticated using(public.is_admin()) with check(public.is_admin());

-- Reviews: clientes autenticados publican directamente; solo pueden crear reseñas a su nombre.
create policy "visible reviews public read" on public.reviews for select to anon,authenticated using(is_visible or user_id=auth.uid() or public.is_admin());
create policy "customer create own review" on public.reviews for insert to authenticated
with check(user_id=auth.uid() and is_visible=true and is_verified=false);
create policy "admin review moderation" on public.reviews for all to authenticated using(public.is_admin()) with check(public.is_admin());

-- Contact messages: public can submit only; no public read/update/delete.
create policy "public submit contact" on public.contact_messages for insert to anon,authenticated with check(true);
create policy "admin manage contact" on public.contact_messages for all to authenticated using(public.is_admin()) with check(public.is_admin());

-- Important hardening notes:
-- 1) The front-end checkout currently inserts orders/items from the authenticated session.
-- 2) For production commerce, replace client-supplied totals/prices with a SECURITY DEFINER
--    checkout RPC that re-reads price/stock and decrements inventory transactionally.
-- 3) Add CAPTCHA/rate limiting (Edge Function/provider) to public contact form.
-- 4) Avoid allowing a customer to modify order totals: use RPC-only INSERT in production.
