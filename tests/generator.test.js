"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { webcrypto } = require("node:crypto");
const generator = require("../script.js");

const allOptions = {
  length: 16, lowercase: true, uppercase: true, digits: true, symbols: true, excludeSimilar: false
};

function makeDocument() {
  const ids = [
    "generatorForm", "passwordLength", "lengthError", "setsError", "passwordOutput",
    "copyButton", "strengthOutput", "recommendation", "statusMessage", "settingsStatus",
    "lowercase", "uppercase", "digits", "symbols", "excludeSimilar"
  ];
  const elements = Object.fromEntries(ids.map((id) => {
    const listeners = new Map();
    return [id, {
      value: "", checked: false, disabled: true, textContent: "", dataset: {}, attributes: {},
      addEventListener(type, callback) {
        if (!listeners.has(type)) listeners.set(type, []);
        listeners.get(type).push(callback);
      },
      setAttribute(name, value) { this.attributes[name] = value; },
      removeAttribute(name) { delete this.attributes[name]; },
      focus() { this.focused = true; },
      async dispatch(type) {
        for (const callback of listeners.get(type) || []) {
          await callback({ preventDefault() {} });
        }
      }
    }];
  }));
  elements.passwordOutput.textContent = "Пароль ещё не создан";
  return { elements, getElementById: (id) => elements[id] };
}

function makeStorage() {
  const values = new Map();
  return {
    getItem: (key) => values.has(key) ? values.get(key) : null,
    setItem: (key, value) => values.set(key, value),
    values
  };
}

test("длина принимает границы и отвергает неверный ввод", () => {
  assert.equal(generator.parseLength("6"), 6);
  assert.equal(generator.parseLength("128"), 128);
  for (const value of ["", "5", "129", "6.5", "1e2", "abc"]) {
    assert.equal(generator.parseLength(value), null);
  }
  assert.throws(() => generator.generatePassword({ ...allOptions, length: 5 }, webcrypto), /Введите целое число/);
});

test("генерация покрывает выбранные наборы и использует разрешённые символы", () => {
  for (const length of [6, 128]) {
    for (let attempt = 0; attempt < 30; attempt += 1) {
      const password = generator.generatePassword({ ...allOptions, length }, webcrypto);
      assert.equal(password.length, length);
      for (const key of ["lowercase", "uppercase", "digits", "symbols"]) {
        assert.ok([...password].some((character) => generator.CHARACTER_SETS[key].includes(character)));
      }
      assert.ok([...password].every((character) => Object.values(generator.CHARACTER_SETS).join("").includes(character)));
    }
  }
  const digitsOnly = generator.generatePassword({ ...allOptions, lowercase: false, uppercase: false, symbols: false }, webcrypto);
  assert.match(digitsOnly, /^\d{16}$/);
  assert.throws(() => generator.generatePassword({ length: 6 }, webcrypto), /Выберите хотя бы один тип символов/);
});

test("похожие символы исключены точно из выбранных наборов", () => {
  const options = { ...allOptions, length: 128, excludeSimilar: true };
  const sets = generator.getSelectedSets(options);
  assert.equal(sets.join(""), Object.values(generator.CHARACTER_SETS).join("").replace(/[O0ol1I]/g, ""));
  for (let attempt = 0; attempt < 30; attempt += 1) {
    assert.doesNotMatch(generator.generatePassword(options, webcrypto), /[O0ol1I]/);
  }
});

test("случайный индекс отклоняет значения, вызывающие смещение", () => {
  const sequence = [0xffffffff, 12];
  let calls = 0;
  const cryptoSource = { getRandomValues(array) { array[0] = sequence[calls++]; return array; } };
  assert.equal(generator.randomIndex(10, cryptoSource), 2);
  assert.equal(calls, 2);
  assert.throws(() => generator.randomIndex(10, null), /HTTPS или localhost/);
});

test("оценка использует формулу и три уровня", () => {
  const onlyLowercase = { ...allOptions, uppercase: false, digits: false, symbols: false };
  assert.equal(generator.evaluateStrength({ ...onlyLowercase, length: 8 }).level, "Слабый");
  assert.equal(generator.evaluateStrength({ ...onlyLowercase, length: 9 }).level, "Средний");
  assert.equal(generator.evaluateStrength({ ...onlyLowercase, length: 13 }).level, "Надёжный");
  assert.equal(generator.evaluateStrength(allOptions).bits, 16 * Math.log2(Object.values(generator.CHARACTER_SETS).join("").length));
  assert.ok(generator.evaluateStrength({ ...allOptions, excludeSimilar: true }).bits < generator.evaluateStrength(allOptions).bits);
});

test("восстановление принимает только допустимые настройки", () => {
  const storage = makeStorage();
  assert.deepEqual(generator.loadSettings(storage), { settings: generator.DEFAULT_SETTINGS, available: true });
  storage.setItem(generator.STORAGE_KEY, JSON.stringify({ ...allOptions, length: 128, excludeSimilar: true }));
  assert.equal(generator.loadSettings(storage).settings.length, 128);
  assert.equal(generator.loadSettings(storage).settings.excludeSimilar, true);
  storage.setItem(generator.STORAGE_KEY, JSON.stringify({ length: 200, lowercase: "false", uppercase: false, digits: false, symbols: false }));
  assert.deepEqual(generator.loadSettings(storage).settings, { ...generator.DEFAULT_SETTINGS, uppercase: false, digits: false, symbols: false });
  storage.setItem(generator.STORAGE_KEY, JSON.stringify({ length: 200, lowercase: false, uppercase: false, digits: false, symbols: false }));
  assert.deepEqual(generator.loadSettings(storage).settings, generator.DEFAULT_SETTINGS);
  storage.setItem(generator.STORAGE_KEY, "not JSON");
  assert.deepEqual(generator.loadSettings(storage), { settings: generator.DEFAULT_SETTINGS, available: true });
});

test("настройки сохраняются, пароль остаётся только в памяти страницы", async () => {
  const storage = makeStorage();
  let copied = "";
  const environment = { localStorage: storage, crypto: webcrypto, navigator: { clipboard: { async writeText(value) { copied = value; } } } };
  const doc = makeDocument();
  generator.initializeGenerator(doc, environment);
  const { elements } = doc;
  assert.equal(elements.copyButton.disabled, true);
  elements.passwordLength.value = "24";
  await elements.passwordLength.dispatch("input");
  assert.equal(JSON.parse(storage.values.get(generator.STORAGE_KEY)).length, 24);
  await elements.generatorForm.dispatch("submit");
  const password = elements.passwordOutput.textContent;
  assert.equal(password.length, 24);
  assert.equal(elements.copyButton.disabled, false);
  assert.match(elements.strengthOutput.textContent, /Надёжный/);
  assert.ok(!storage.values.get(generator.STORAGE_KEY).includes(password));
  await elements.copyButton.dispatch("click");
  assert.equal(copied, password);
  assert.equal(elements.statusMessage.textContent, "Пароль скопирован");

  elements.passwordLength.value = "5";
  await elements.passwordLength.dispatch("input");
  await elements.generatorForm.dispatch("submit");
  assert.equal(elements.lengthError.textContent, "Введите целое число от 6 до 128");
  assert.equal(elements.passwordOutput.textContent, password);
  assert.equal(JSON.parse(storage.values.get(generator.STORAGE_KEY)).length, 24);

  const reopened = makeDocument();
  generator.initializeGenerator(reopened, environment);
  assert.equal(reopened.elements.passwordLength.value, "24");
  assert.equal(reopened.elements.passwordOutput.textContent, "Пароль ещё не создан");
  assert.equal(reopened.elements.copyButton.disabled, true);
});

test("недоступное хранилище и ошибка копирования не мешают генерации", async () => {
  const storage = { getItem() { throw new Error("blocked"); }, setItem() { throw new Error("blocked"); } };
  const environment = { localStorage: storage, crypto: webcrypto, navigator: { clipboard: { async writeText() { throw new Error("blocked"); } } } };
  const doc = makeDocument();
  generator.initializeGenerator(doc, environment);
  const { elements } = doc;
  assert.equal(elements.settingsStatus.textContent, "Не удалось сохранить настройки");
  elements.passwordLength.value = "6";
  await elements.passwordLength.dispatch("input");
  await elements.generatorForm.dispatch("submit");
  const password = elements.passwordOutput.textContent;
  assert.equal(password.length, 6);
  await elements.copyButton.dispatch("click");
  assert.equal(elements.statusMessage.textContent, "Не удалось скопировать пароль");
  assert.equal(elements.passwordOutput.textContent, password);
});
