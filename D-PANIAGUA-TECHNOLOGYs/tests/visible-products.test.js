const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { test } = require("node:test");

const projectRoot = path.resolve(__dirname, "..");

function makeDatabase(product) {
  return {
    from() {
      const filters = [];
      let columns = "";
      const query = {
        select(value) {
          columns = value;
          return this;
        },
        eq(column, value) {
          filters.push([column, value]);
          return this;
        },
        limit() {
          return this;
        },
        then(resolve, reject) {
          const asksForMissingStatus = filters.some(([column]) => column === "status");
          const asksForMissingOfferLabel = columns.includes("offer_label");
          const result = asksForMissingStatus || asksForMissingOfferLabel
            ? { data: null, error: { code: "42703", message: "column does not exist" } }
            : { data: [product], error: null };
          return Promise.resolve(result).then(resolve, reject);
        }
      };
      return query;
    }
  };
}

async function renderProducts(scriptName, hostId, overrides = {}) {
  const product = {
    id: "product-1",
    name: "Producto publicado",
    brand: "Marca",
    description: "Producto de prueba",
    price: 100,
    stock: 2,
    image_url: "product.jpg",
    is_published: true,
    categories: { slug: "celulares", name: "Celulares" },
    ...overrides
  };
  const host = { innerHTML: "" };
  const document = {
    body: { dataset: { category: "celulares" } },
    querySelector(selector) {
      if (selector === hostId) return host;
      return null;
    }
  };
  const window = {
    DP: {
      db: makeDatabase(product),
      demoProducts: [],
      productCard: (item) => `<article>${item.name}</article>`
    }
  };
  const source = fs.readFileSync(path.join(projectRoot, "js", scriptName), "utf8");

  vm.runInNewContext(source, {
    window,
    document,
    location: { search: "" },
    URLSearchParams
  });
  await new Promise((resolve) => setImmediate(resolve));
  return host.innerHTML;
}

test("category listings still show published products before the commerce migration", async () => {
  const html = await renderProducts("productos.js", "#productGrid");
  assert.match(html, /Producto publicado/);
  assert.doesNotMatch(html, /No se pudieron cargar los productos/);
});

test("the home page still shows published products before the commerce migration", async () => {
  const html = await renderProducts("inicio.js", "#featuredProducts");
  assert.match(html, /Producto publicado/);
  assert.doesNotMatch(html, /No se pudieron cargar los productos/);
});

test("products marked inactive stay hidden after the commerce migration", async () => {
  const html = await renderProducts("productos.js", "#productGrid", { status: "inactive" });
  assert.doesNotMatch(html, /Producto publicado/);
  assert.match(html, /No encontramos productos/);
});
