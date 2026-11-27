const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { test } = require("node:test");

const projectRoot = path.resolve(__dirname, "..");

function makeDatabase(products) {
  return {
    from() {
      const query = {
        select() { return this; },
        eq() { return this; },
        order() { return this; },
        then(resolve, reject) {
          return Promise.resolve({ data: products, error: null }).then(resolve, reject);
        },
      };
      return query;
    },
  };
}

async function renderCatalog(search) {
  const handlers = new Map();
  const products = [
    {
      id: "laptop-1",
      name: "Laptop de muestra",
      brand: "Nova",
      description: "Equipo para trabajo",
      price: 500,
      status: "active",
      categories: { name: "Laptops", slug: "laptops" },
    },
    {
      id: "mouse-1",
      name: "Mouse inalámbrico",
      brand: "Nova",
      description: "Accesorio para laptop",
      price: 25,
      status: "active",
      categories: { name: "Accesorios", slug: "accesorios" },
    },
  ];
  const host = { innerHTML: "" };
  const searchInput = {
    value: "",
    focus() {},
    addEventListener(type, handler) { handlers.set(`search:${type}`, handler); },
  };
  const categoryFilter = {
    value: "",
    options: [],
    append(option) { this.options.push(option); },
    addEventListener(type, handler) { handlers.set(`category:${type}`, handler); },
  };
  const sortFilter = {
    value: "featured",
    addEventListener(type, handler) { handlers.set(`sort:${type}`, handler); },
  };
  const resultCount = { textContent: "" };
  const searchNotice = { textContent: "" };
  const demoNote = { classList: { add() {}, remove() {} } };
  const searchForm = {
    addEventListener(type, handler) { handlers.set(`form:${type}`, handler); },
  };
  const elements = new Map([
    ["#productGrid", host],
    ["#catalogSearchForm", searchForm],
    ["#productSearch", searchInput],
    ["#categoryFilter", categoryFilter],
    ["#sortProducts", sortFilter],
    ["#productCount", resultCount],
    ["#searchNotice", searchNotice],
    ["[data-demo-note]", demoNote],
  ]);
  const document = {
    querySelector(selector) { return elements.get(selector) || null; },
    querySelectorAll() { return []; },
    createElement() { return { value: "", textContent: "" }; },
  };
  const window = {
    location: { search },
    DP: {
      db: makeDatabase(products),
      demoProducts: [],
      productCard: (product) => `<article>${product.name}</article>`,
    },
  };
  const context = {
    document,
    location: { href: "" },
    localStorage: { getItem: () => "[]" },
    URLSearchParams,
    window,
    clearTimeout() {},
    setTimeout() { return 1; },
  };

  vm.runInNewContext(fs.readFileSync(path.join(projectRoot, "js", "global.js"), "utf8"), context);
  vm.runInNewContext(fs.readFileSync(path.join(projectRoot, "js", "buscar.js"), "utf8"), context);
  await new Promise((resolve) => setImmediate(resolve));

  return { host, searchInput, categoryFilter, resultCount, handlers };
}

test("catalog page searches every category and applies the selected category", async () => {
  const catalog = await renderCatalog("?q=mouse");

  assert.equal(catalog.searchInput.value, "mouse");
  assert.match(catalog.host.innerHTML, /Mouse inalámbrico/);
  assert.doesNotMatch(catalog.host.innerHTML, /Laptop de muestra/);
  assert.equal(catalog.resultCount.textContent, "1 producto encontrado");

  catalog.categoryFilter.value = "laptops";
  catalog.handlers.get("category:change")();

  assert.match(catalog.host.innerHTML, /No encontramos productos/);
  assert.equal(catalog.resultCount.textContent, "0 productos encontrados");
});
