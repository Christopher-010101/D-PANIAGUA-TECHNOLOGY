# Porcentaje de descuento para productos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Dejar que el administrador ingrese el precio base y un descuento opcional en porcentaje para calcular y guardar automáticamente el precio de oferta.

**Architecture:** Añadir una función pequeña y pura de cálculo a `js/admin.js`, usada por los formularios de crear y editar. Mostrar precio base, descuento y vista previa; al guardar, mantener la representación existente en Supabase (`price` final, `compare_at_price` base).

**Tech Stack:** HTML, CSS existente, JavaScript nativo, Supabase existente, `node:test`.

**Spec:** `docs/superpowers/specs/2026-11-26-ofertas-con-descuento-porcentaje.md`

## Global Constraints

- Mantener la identidad visual oscura, roja y blanca existente.
- No agregar migraciones SQL ni nuevas columnas.
- Usar `price` para el precio final y `compare_at_price` para el precio base cuando el descuento sea mayor que cero.
- Un descuento vacío o igual a cero elimina la oferta; permitir de 0 a 100 y calcular a dos decimales.
- Aplicar la función tanto al crear como al editar cualquier producto.

## Review Focus

- Descuento vacío o cero: se guarda al precio base y se quita el precio anterior.
- Descuento de 100%: se acepta y produce un precio final cero.
- Descuento negativo, mayor que 100 o precio base negativo: se rechaza antes de guardar.
- Precios con fracciones de centavo tras el descuento: se redondean a dos decimales.
- Descuento demasiado pequeño para cambiar el precio en centavos: no se publica una oferta sin ahorro real.
- Al editar un producto con oferta existente: se precargan su base y porcentaje derivado; al editar uno sin oferta: el descuento aparece en cero.
- Editar y guardar una oferta existente conserva su precio exacto aunque el porcentaje derivado necesite más decimales.

---

### Task 1: Cálculo reutilizable del precio de oferta

**Files:**
- Modify: `js/admin.js`
- Test: `tests/product-offer-pricing.test.js`

**Interfaces:**
- Produce: `window.DP.calculateOfferPricing(basePrice, discountPercent)`, que retorna `price`, `compare_at_price`, `discount_percent` y `savings`, o lanza `RangeError` en datos fuera de rango.

- [x] **Step 1: Escribir pruebas fallidas** para precio sin descuento, descuento 15%, redondeo, descuento minúsculo sin ahorro, 100% y valores fuera de rango.
- [x] **Step 2: Ejecutar** `node --test tests/product-offer-pricing.test.js` y confirmar que fallan porque la función aún no existe.
- [x] **Step 3: Implementar** la función pura en `js/admin.js` y redondear el precio final a dos decimales.
- [x] **Step 4: Ejecutar** `node --test tests/product-offer-pricing.test.js` y confirmar que todas pasan.

### Task 2: Formularios de alta y edición de productos

**Files:**
- Modify: `admin/productos.html`
- Modify: `js/admin.js`
- Modify: `tests/product-offer-pricing.test.js`

**Interfaces:**
- Consume: `window.DP.calculateOfferPricing(basePrice, discountPercent)`.
- Persiste el descuento calculado usando las columnas actuales `price` y `compare_at_price`.

- [x] **Step 1: Extender pruebas** para precargar el precio base y porcentaje de productos con y sin oferta, y conservar el precio exacto al editar una oferta existente.
- [x] **Step 2: Ejecutar** `node --test tests/product-offer-pricing.test.js` y confirmar que el nuevo caso falla antes del cambio.
- [x] **Step 3: Actualizar ambos formularios** para ingresar precio base y porcentaje opcional, con vista previa del precio final y ahorro.
- [x] **Step 4: Actualizar el código de productos** para precargar ofertas existentes, permitir modificar/eliminar descuentos, calcular al guardar y validar los datos.
- [x] **Step 5: Ejecutar** `node --test tests/product-offer-pricing.test.js` y `node --check` en los archivos JavaScript modificados.
- [x] **Step 6: Revisar** que el HTML contenga un campo de precio base y descuento en los formularios de creación y edición, y que ya no solicite al administrador ingresar ambos precios manualmente.

