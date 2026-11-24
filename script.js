"use strict";

const CHARACTER_SETS = Object.freeze({
  lowercase: "abcdefghijklmnopqrstuvwxyz",
  uppercase: "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
  digits: "0123456789",
  symbols: "!@#$%^&*()-_=+[]{};:,.?"
});
const SET_KEYS = Object.keys(CHARACTER_SETS);
const SIMILAR_CHARACTERS = new Set("O0ol1I");
const LENGTH_ERROR = "Введите целое число от 6 до 128";
const SETS_ERROR = "Выберите хотя бы один тип символов";

function parseLength(value) {
  const text = String(value).trim();
  if (!/^\d+$/.test(text)) return null;
  const length = Number(text);
  return Number.isInteger(length) && length >= 6 && length <= 128 ? length : null;
}

function getSelectedSets(options) {
  return SET_KEYS
    .filter((key) => options[key] === true)
    .map((key) => {
      const characters = CHARACTER_SETS[key];
      return options.excludeSimilar
        ? [...characters].filter((character) => !SIMILAR_CHARACTERS.has(character)).join("")
        : characters;
    });
}

function randomIndex(max, cryptoSource = globalThis.crypto) {
  if (!cryptoSource || typeof cryptoSource.getRandomValues !== "function") {
    throw new Error("Для генерации требуется HTTPS или localhost");
  }
  // Rejection sampling removes modulo bias from a 32-bit random value.
  const range = 0x100000000;
  const limit = range - (range % max);
  const value = new Uint32Array(1);
  do {
    cryptoSource.getRandomValues(value);
  } while (value[0] >= limit);
  return value[0] % max;
}

function generatePassword(options, cryptoSource = globalThis.crypto) {
  if (!Number.isInteger(options.length) || options.length < 6 || options.length > 128) {
    throw new RangeError(LENGTH_ERROR);
  }
  const sets = getSelectedSets(options);
  if (sets.length === 0) throw new RangeError(SETS_ERROR);

  const pool = sets.join("");
  const characters = sets.map((set) => set[randomIndex(set.length, cryptoSource)]);
  while (characters.length < options.length) {
    characters.push(pool[randomIndex(pool.length, cryptoSource)]);
  }

  for (let index = characters.length - 1; index > 0; index -= 1) {
    const swapIndex = randomIndex(index + 1, cryptoSource);
    [characters[index], characters[swapIndex]] = [characters[swapIndex], characters[index]];
  }
  return characters.join("");
}

function initializeGenerator(doc = document) {
  const form = doc.getElementById("generatorForm");
  const lengthInput = doc.getElementById("passwordLength");
  const lengthError = doc.getElementById("lengthError");
  const setsError = doc.getElementById("setsError");
  const passwordOutput = doc.getElementById("passwordOutput");
  const statusMessage = doc.getElementById("statusMessage");
  let currentPassword = "";

  function readOptions() {
    const options = { length: parseLength(lengthInput.value) };
    for (const key of SET_KEYS) options[key] = doc.getElementById(key).checked;
    options.excludeSimilar = doc.getElementById("excludeSimilar").checked;
    return options;
  }

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    lengthError.textContent = "";
    setsError.textContent = "";
    statusMessage.textContent = "";
    lengthInput.removeAttribute("aria-invalid");

    const options = readOptions();
    if (options.length === null) {
      lengthError.textContent = LENGTH_ERROR;
      lengthInput.setAttribute("aria-invalid", "true");
      lengthInput.focus();
      return;
    }
    if (getSelectedSets(options).length === 0) {
      setsError.textContent = SETS_ERROR;
      doc.getElementById("lowercase").focus();
      return;
    }

    try {
      currentPassword = generatePassword(options);
      passwordOutput.textContent = currentPassword;
    } catch (error) {
      statusMessage.textContent = error.message;
    }
  });

  return { getCurrentPassword: () => currentPassword };
}

if (typeof document !== "undefined") {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => initializeGenerator());
  } else {
    initializeGenerator();
  }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { CHARACTER_SETS, parseLength, getSelectedSets, randomIndex, generatePassword, initializeGenerator };
}
