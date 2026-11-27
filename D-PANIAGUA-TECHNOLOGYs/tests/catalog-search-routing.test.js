import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import test from "node:test";

const globalScript = fs.readFileSync(new URL("../js/global.js", import.meta.url), "utf8");
const homePageMarkup = fs.readFileSync(new URL("../index.html", import.meta.url), "utf8");
const publicPageMarkup = fs.readdirSync(new URL("../", import.meta.url))
  .filter((fileName) => fileName.endsWith(".html"))
  .map((fileName) => fs.readFileSync(new URL(`../${fileName}`, import.meta.url), "utf8"))
  .join("\n");

test("homepage search opens the full catalog with the encoded query", () => {
  let submitHandler;
  const form = {
    addEventListener(type, handler) {
      if (type === "submit") submitHandler = handler;
    },
    querySelector() {
      return { value: " laptop + mouse " };
    },
  };
  const document = {
    querySelector() {
      return null;
    },
    querySelectorAll(selector) {
      return selector === "[data-search-form]" ? [form] : [];
    },
  };
  const location = { href: "" };
  const window = { DP: { supabaseReady: true } };
  const context = {
    document,
    location,
    localStorage: { getItem: () => "[]" },
    window,
    clearTimeout() {},
    setTimeout() { return 1; },
  };

  vm.runInNewContext(globalScript, context);
  submitHandler({ preventDefault() {} });

  assert.equal(location.href, "buscar.html?q=laptop%20%2B%20mouse");
});

test("catalog filters search across categories and sort matching products by price", () => {
  const document = {
    querySelector() {
      return null;
    },
    querySelectorAll() {
      return [];
    },
  };
  const window = { DP: { supabaseReady: true } };
  const context = {
    document,
    location: { href: "" },
    localStorage: { getItem: () => "[]" },
    window,
    clearTimeout() {},
    setTimeout() { return 1; },
  };
  const products = [
    { name: "Laptop Pro", brand: "Nova", description: "", category_slug: "laptops", price: 900 },
    { name: "Mouse inalámbrico", brand: "Nova", description: "", category_slug: "accesorios", price: 25 },
    { name: "Laptop Air", brand: "Delta", description: "", category_slug: "laptops", price: 500 },
  ];

  vm.runInNewContext(globalScript, context);
  assert.equal(typeof window.DP.filterCatalogProducts, "function");
  if (typeof window.DP.filterCatalogProducts !== "function") return;

  const filtered = window.DP.filterCatalogProducts(products, {
    query: "laptop",
    categorySlug: "",
    sort: "low",
  });

  assert.deepEqual(Array.from(filtered, (product) => product.name), ["Laptop Air", "Laptop Pro"]);
});

test("homepage does not present sample testimonials as real customer feedback", () => {
  assert.doesNotMatch(homePageMarkup, /Denzel Aquino|Cristal Castro|Richard Santana/);
  assert.match(homePageMarkup, /href="contacto\.html"/);
});

test("public pages do not show demonstration contact details as official channels", () => {
  assert.doesNotMatch(publicPageMarkup, /contacto@dpaniagua\.example|contacto@dpaniaguatechnology|555-0142/);
  assert.doesNotMatch(publicPageMarkup, /Contacto demo|Teléfono de demostración|Correo de demostración/);
});

test("mobile menu reports its expanded state to assistive technology", () => {
  let toggleHandler;
  let isOpen = false;
  const attributes = new Map([
    ["aria-expanded", "false"],
    ["aria-label", "Abrir menú"],
  ]);
  const menuButton = {
    addEventListener(type, handler) {
      if (type === "click") toggleHandler = handler;
    },
    setAttribute(name, value) {
      attributes.set(name, value);
    },
  };
  const navigation = {
    classList: {
      toggle(className) {
        assert.equal(className, "open");
        isOpen = !isOpen;
        return isOpen;
      },
    },
  };
  const document = {
    querySelector(selector) {
      if (selector === "#menuToggle") return menuButton;
      if (selector === "#navLinks") return navigation;
      return null;
    },
    querySelectorAll() {
      return [];
    },
  };
  const context = {
    document,
    location: { href: "" },
    localStorage: { getItem: () => "[]" },
    window: { DP: { supabaseReady: true } },
    clearTimeout() {},
    setTimeout() { return 1; },
  };

  vm.runInNewContext(globalScript, context);
  toggleHandler();
  assert.equal(attributes.get("aria-expanded"), "true");
  assert.equal(attributes.get("aria-label"), "Cerrar menú");

  toggleHandler();
  assert.equal(attributes.get("aria-expanded"), "false");
  assert.equal(attributes.get("aria-label"), "Abrir menú");
});
