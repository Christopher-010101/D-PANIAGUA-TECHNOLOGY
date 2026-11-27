const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const adminScript = fs.readFileSync(path.join(__dirname, "..", "js", "admin.js"), "utf8");
const sandbox = {
  window: { DP: { db: null } },
  document: { querySelector: () => ({ textContent: "", classList: { remove() {}, add() {} } }) },
  console
};
vm.runInNewContext(adminScript, sandbox, { filename: "js/admin.js" });

function calculateOfferPricing(basePrice, discountPercent) {
  return JSON.parse(JSON.stringify(
    sandbox.window.DP.calculateOfferPricing(basePrice, discountPercent)
  ));
}

function getOfferFormValues(product) {
  return JSON.parse(JSON.stringify(sandbox.window.DP.getOfferFormValues(product)));
}

test("no discount keeps the base price and removes the compare-at price", () => {
  assert.deepEqual(calculateOfferPricing("1250.00", ""), {
    price: 1250,
    compare_at_price: null,
    discount_percent: 0,
    savings: 0
  });
});

test("a 15 percent discount calculates sale price, base price, and savings", () => {
  assert.deepEqual(calculateOfferPricing("1000", "15"), {
    price: 850,
    compare_at_price: 1000,
    discount_percent: 15,
    savings: 150
  });
});

test("offer prices and savings round to cents", () => {
  assert.deepEqual(calculateOfferPricing("199.99", "15"), {
    price: 169.99,
    compare_at_price: 199.99,
    discount_percent: 15,
    savings: 30
  });
});

test("a discount too small to change the cent price does not create a false offer", () => {
  assert.deepEqual(calculateOfferPricing("1.00", "0.01"), {
    price: 1,
    compare_at_price: null,
    discount_percent: 0.01,
    savings: 0
  });
});

test("a 100 percent discount sets the offer price to zero", () => {
  assert.deepEqual(calculateOfferPricing("250", "100"), {
    price: 0,
    compare_at_price: 250,
    discount_percent: 100,
    savings: 250
  });
});

test("invalid prices and discounts outside zero to one hundred are rejected", () => {
  assert.throws(() => calculateOfferPricing("-1", "15"), { name: "RangeError" });
  assert.throws(() => calculateOfferPricing("100", "-1"), { name: "RangeError" });
  assert.throws(() => calculateOfferPricing("100", "100.01"), { name: "RangeError" });
  assert.throws(() => calculateOfferPricing("not-a-price", "15"), { name: "RangeError" });
});

test("editing an offered product preloads its base price and discount percent", () => {
  assert.deepEqual(getOfferFormValues({ price: 850, compare_at_price: 1000 }), {
    basePrice: 1000,
    discountPercent: 15
  });
});

test("editing and saving an existing offer preserves its exact sale price", () => {
  const existingProduct = { price: 6666.66, compare_at_price: 10000 };
  const formValues = getOfferFormValues(existingProduct);
  const savedPricing = calculateOfferPricing(formValues.basePrice, formValues.discountPercent);

  assert.equal(savedPricing.price, existingProduct.price);
  assert.equal(savedPricing.compare_at_price, existingProduct.compare_at_price);
});

test("editing a product without an offer preloads zero discount", () => {
  assert.deepEqual(getOfferFormValues({ price: 1200, compare_at_price: null }), {
    basePrice: 1200,
    discountPercent: 0
  });
});
