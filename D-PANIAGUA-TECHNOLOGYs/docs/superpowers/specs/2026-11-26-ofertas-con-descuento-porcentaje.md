# Diseño: descuentos porcentuales en productos

## Objetivo

Simplificar la creación y edición de ofertas de productos. El administrador ingresa el precio base y, si quiere una oferta, un porcentaje de descuento. El sistema calcula y muestra el precio final y el ahorro.

## Alcance y comportamiento

- Aplicar a los formularios de crear y editar cualquier producto.
- Permitir cambiar el descuento o quitarlo; sin descuento, guardar el producto al precio base y sin precio anterior/oferta.
- Calcular el precio final redondeado a centavos y mostrar una vista previa antes de guardar.
- Conservar el esquema actual de Supabase: `products.price` guarda el precio final y `products.compare_at_price` guarda el precio base solo cuando hay descuento.
- Al editar ofertas existentes, derivar el porcentaje guardado a partir de `price` y `compare_at_price`.
- Los combos siguen calculando ahorro a partir de los precios de sus productos incluidos.

## Enfoques considerados

- **Precio base + porcentaje, elegido:** coincide con el flujo solicitado y permite editar o quitar ofertas; reutiliza las columnas y el formato de precios que ya consumen la tienda y el carrito.
- Precio base + descuento fijo en RD$: no se elige porque la usuaria indicó que quiere escribir porcentajes como 15%.
- Ingresar precio actual y anterior: se descarta porque requiere escribir ambos valores manualmente.

## Restricciones

- No cambiar colores, identidad visual ni proceso de pago.
- Validar descuento de 0 a 100 inclusive y mostrar cálculos monetarios a dos decimales.
- No agregar columnas ni requerir una migración SQL.
