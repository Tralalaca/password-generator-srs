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
const STORAGE_KEY = "password-generator-settings-v1";
const DEFAULT_SETTINGS = Object.freeze({
  length: 16,
  lowercase: true,
  uppercase: true,
  digits: true,
  symbols: true,
  excludeSimilar: false
});

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

function evaluateStrength(options) {
  const alphabetSize = getSelectedSets(options).join("").length;
  if (alphabetSize === 0) throw new RangeError(SETS_ERROR);
  const bits = options.length * Math.log2(alphabetSize);
  const level = bits < 40 ? "Слабый" : bits < 60 ? "Средний" : "Надёжный";
  return { bits, level };
}

function normalizeSavedSettings(candidate) {
  const settings = { ...DEFAULT_SETTINGS };
  if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) return settings;
  if (Number.isInteger(candidate.length) && candidate.length >= 6 && candidate.length <= 128) {
    settings.length = candidate.length;
  }
  for (const key of [...SET_KEYS, "excludeSimilar"]) {
    if (typeof candidate[key] === "boolean") settings[key] = candidate[key];
  }
  if (!SET_KEYS.some((key) => settings[key])) {
    for (const key of SET_KEYS) settings[key] = DEFAULT_SETTINGS[key];
  }
  return settings;
}

function loadSettings(storage) {
  if (!storage || typeof storage.getItem !== "function") {
    return { settings: { ...DEFAULT_SETTINGS }, available: false };
  }
  let saved;
  try {
    saved = storage.getItem(STORAGE_KEY);
  } catch {
    return { settings: { ...DEFAULT_SETTINGS }, available: false };
  }
  if (saved === null) return { settings: { ...DEFAULT_SETTINGS }, available: true };
  try {
    return { settings: normalizeSavedSettings(JSON.parse(saved)), available: true };
  } catch {
    return { settings: { ...DEFAULT_SETTINGS }, available: true };
  }
}

function saveSettings(storage, settings) {
  try {
    if (!storage || typeof storage.setItem !== "function") return false;
    storage.setItem(STORAGE_KEY, JSON.stringify(settings));
    return true;
  } catch {
    return false;
  }
}

function initializeGenerator(doc = document, environment = globalThis) {
  const form = doc.getElementById("generatorForm");
  const lengthInput = doc.getElementById("passwordLength");
  const lengthError = doc.getElementById("lengthError");
  const setsError = doc.getElementById("setsError");
  const passwordOutput = doc.getElementById("passwordOutput");
  const copyButton = doc.getElementById("copyButton");
  const strengthOutput = doc.getElementById("strengthOutput");
  const recommendation = doc.getElementById("recommendation");
  const statusMessage = doc.getElementById("statusMessage");
  const settingsStatus = doc.getElementById("settingsStatus");
  let currentPassword = "";
  let storage;
  try { storage = environment.localStorage; } catch { storage = null; }
  const restored = loadSettings(storage);
  let lastValidLength = restored.settings.length;
  lengthInput.value = String(restored.settings.length);
  for (const key of SET_KEYS) doc.getElementById(key).checked = restored.settings[key];
  doc.getElementById("excludeSimilar").checked = restored.settings.excludeSimilar;
  if (!restored.available) settingsStatus.textContent = "Не удалось сохранить настройки";

  function readOptions() {
    const options = { length: parseLength(lengthInput.value) };
    for (const key of SET_KEYS) options[key] = doc.getElementById(key).checked;
    options.excludeSimilar = doc.getElementById("excludeSimilar").checked;
    return options;
  }

  function persistSettings() {
    const options = readOptions();
    if (options.length !== null) lastValidLength = options.length;
    const settings = { ...options, length: lastValidLength };
    settingsStatus.textContent = saveSettings(storage, settings) ? "" : "Не удалось сохранить настройки";
  }

  lengthInput.addEventListener("input", persistSettings);
  for (const key of [...SET_KEYS, "excludeSimilar"]) {
    doc.getElementById(key).addEventListener("change", persistSettings);
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
      currentPassword = generatePassword(options, environment.crypto);
      passwordOutput.textContent = currentPassword;
      copyButton.disabled = false;
      const strength = evaluateStrength(options);
      strengthOutput.textContent = `Оценка стойкости: ${strength.level} (${strength.bits.toFixed(1)} бит)`;
      strengthOutput.dataset.level = strength.level === "Слабый" ? "weak" : strength.level === "Средний" ? "medium" : "strong";
      recommendation.textContent = strength.level === "Надёжный"
        ? ""
        : "Увеличьте длину пароля или выберите больше типов символов.";
    } catch (error) {
      statusMessage.textContent = error.message;
    }
  });

  copyButton.addEventListener("click", async () => {
    if (!currentPassword) return;
    try {
      if (!environment.navigator?.clipboard?.writeText) throw new Error("Clipboard API недоступен");
      await environment.navigator.clipboard.writeText(currentPassword);
      statusMessage.textContent = "Пароль скопирован";
    } catch {
      statusMessage.textContent = "Не удалось скопировать пароль";
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
  module.exports = {
    CHARACTER_SETS, DEFAULT_SETTINGS, STORAGE_KEY, parseLength, getSelectedSets, randomIndex,
    generatePassword, evaluateStrength, normalizeSavedSettings, loadSettings, saveSettings, initializeGenerator
  };
}
