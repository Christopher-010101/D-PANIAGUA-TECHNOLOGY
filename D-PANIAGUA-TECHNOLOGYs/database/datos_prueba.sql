-- Catálogo de demostración con modelos comerciales y fotografías de producto.
-- Los precios (DOP) y existencias son ilustrativos; verificar inventario y precios antes de publicar.
insert into public.categories(name,slug,description) values
('Celulares','celulares','Teléfonos inteligentes'),
('Laptops y computadoras','laptops','Equipos portátiles y de escritorio'),
('Tablets','tablets','Tablets para estudio y entretenimiento'),
('Televisores','televisores','Televisores y pantallas'),
('Electrodomésticos','electrodomesticos','Electrodomésticos para el hogar'),
('Accesorios tecnológicos','accesorios','Audífonos y accesorios')
on conflict(slug) do update set name=excluded.name,description=excluded.description;

-- Quita únicamente los artículos ficticios de la versión anterior del catálogo demo.
delete from public.products where name in (
 'Nova X Pro 256 GB','Smartphone Lite 128 GB','ProBook Creator 16','Tab Air 11',
 'Vision 4K Smart TV 55','Refrigerador Frost 18 pies','Audífonos Wireless ANC','Laptop Student 15'
);

-- La clave única permite volver a ejecutar este archivo sin duplicar productos.
create unique index if not exists products_category_name_uidx on public.products(category_id,name);

insert into public.products(category_id,name,brand,description,price,compare_at_price,stock,image_url,features,is_published)
select c.id,v.name,v.brand,v.description,v.price,v.old_price,v.stock,v.image,v.features,true
from (values
('celulares','Samsung Galaxy A15 128 GB','Samsung','Smartphone con pantalla Super AMOLED de 6.5 pulgadas y cámara principal de 50 MP.',8995::numeric,9995::numeric,12,'https://i5.walmartimages.com/asr/2f4a87e3-a16b-4f64-baff-6135548a4eba.02ae1b3626c91207e5cc76c666616d4a.jpeg?odnBg=FFFFFF&odnHeight=768&odnWidth=768',array['128 GB','Super AMOLED','50 MP']),
('laptops','Lenovo IdeaPad Slim 3 15.6"','Lenovo','Laptop para estudio y productividad con Intel Core i7, 16 GB RAM y SSD de 512 GB.',32995::numeric,35995::numeric,6,'https://cdn11.bigcommerce.com/s-sp9oc95xrw/images/stencil/1280x1280/products/19088/71372/82X7006LAX__18628.1701425037.jpg?c=2',array['Intel Core i7','16 GB RAM','SSD 512 GB']),
('tablets','Samsung Galaxy Tab 8.7"','Samsung','Tablet compacta para lectura, clases, navegación y entretenimiento.',9995::numeric,null::numeric,9,'https://media.ipcstore.net/img/21312197_1.jpg',array['8.7 pulgadas','64 GB','Wi-Fi']),
('televisores','LG UHD 4K Smart TV 55"','LG','Televisor LG de 55 pulgadas con resolución UHD 4K y funciones Smart TV.',27995::numeric,31995::numeric,4,'https://www.lg.com/ru/images/televisions/md06099956/gallery/UM7300_55_large.jpg',array['55 pulgadas','UHD 4K','Smart TV']),
('electrodomesticos','Refrigerador LG Smart Inverter','LG','Refrigerador de dos puertas con compresor Smart Inverter y amplio espacio interior.',42995::numeric,null::numeric,3,'https://bf1af2.akinoncloudcdn.com/products/2024/09/19/35795/cdcf4c29-2fd4-4d5a-834b-59a3fbf7ad36_size3840_cropCenter.jpg',array['Smart Inverter','Dos puertas','438 litros']),
('accesorios','Audífonos inalámbricos Sony','Sony','Audífonos over-ear inalámbricos para música, llamadas y uso diario.',4995::numeric,5995::numeric,18,'https://assets.mmsrg.com/isr/166325/c1/-/ASSET_MMS_102745011',array['Bluetooth','Over-ear','Micrófono integrado'])
) as v(slug,name,brand,description,price,old_price,stock,image,features)
join public.categories c on c.slug=v.slug
on conflict(category_id,name) do update set
 brand=excluded.brand,description=excluded.description,price=excluded.price,
 compare_at_price=excluded.compare_at_price,stock=excluded.stock,image_url=excluded.image_url,
 features=excluded.features,is_published=true,updated_at=now();
