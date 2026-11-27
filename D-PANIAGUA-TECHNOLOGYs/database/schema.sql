-- D'Paniagua Technology | PostgreSQL / Supabase
create extension if not exists pgcrypto;

create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text,
 role text not null default 'customer' check (role in ('admin','customer')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.categories (
 id uuid primary key default gen_random_uuid(),
 name text not null unique,
 slug text not null unique,
 description text,
 created_at timestamptz not null default now()
);
create table if not exists public.products (
 id uuid primary key default gen_random_uuid(),
 category_id uuid not null references public.categories(id) on delete restrict,
 name text not null,
 brand text,
 description text not null default '',
 price numeric(12,2) not null check(price>=0),
 compare_at_price numeric(12,2) check(compare_at_price is null or compare_at_price>=price),
 stock integer not null default 0 check(stock>=0),
 image_url text,
 features text[] not null default '{}',
 is_published boolean not null default false,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.orders (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete restrict,
 total numeric(12,2) not null check(total>=0),
 status text not null default 'pending' check(status in ('pending','confirmed','processing','shipped','completed','cancelled')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.order_items (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.orders(id) on delete cascade,
 product_id uuid not null references public.products(id) on delete restrict,
 quantity integer not null check(quantity>0),
 unit_price numeric(12,2) not null check(unit_price>=0),
 created_at timestamptz not null default now(),
 unique(order_id,product_id)
);
create table if not exists public.reviews (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 product_id uuid references public.products(id) on delete cascade,
 display_name text not null check(length(trim(display_name))>=2),
 rating integer not null check(rating between 1 and 5),
 body text not null check(length(trim(body)) between 10 and 1200),
 is_visible boolean not null default false,
 is_verified boolean not null default false,
 created_at timestamptz not null default now()
);
create table if not exists public.contact_messages (
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(trim(name))>=2),
 email text not null,
 phone text,
 subject text not null,
 message text not null check(length(trim(message)) between 10 and 3000),
 status text not null default 'new' check(status in ('new','read','resolved')),
 created_at timestamptz not null default now()
);

create index if not exists products_category_published_idx on public.products(category_id,is_published);
create unique index if not exists products_category_name_uidx on public.products(category_id,name);
create index if not exists orders_user_created_idx on public.orders(user_id,created_at desc);
create index if not exists order_items_order_idx on public.order_items(order_id);
create index if not exists reviews_visible_created_idx on public.reviews(is_visible,created_at desc);
create index if not exists reviews_product_visible_idx on public.reviews(product_id,is_visible,created_at desc);
create unique index if not exists reviews_one_per_user_product_uidx on public.reviews(user_id,product_id) where product_id is not null;
create index if not exists contact_messages_created_idx on public.contact_messages(created_at desc);

-- Create a profile automatically for every new Auth user. Role is always customer;
-- promotion to admin is a separate trusted SQL-console operation.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
 insert into public.profiles(id,full_name,role)
 values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''), 'customer')
 on conflict(id) do nothing;
 return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$
 select exists(select 1 from public.profiles where id=auth.uid() and role='admin');
$$;
