"""Checks for the laboratory SQLite schema and its sample data."""

from pathlib import Path
import sqlite3
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCHEMA = (ROOT / "database" / "schema.sql").read_text(encoding="utf-8")
SEED = (ROOT / "database" / "seed_data.sql").read_text(encoding="utf-8")


class DatabaseSchemaTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.db.executescript(SCHEMA)
        self.db.executescript(SEED)

    def tearDown(self):
        self.db.close()

    def test_seed_represents_generator_settings_without_passwords(self):
        configs = self.db.execute(
            "SELECT name, password_length, exclude_similar FROM generator_configs ORDER BY config_id"
        ).fetchall()
        self.assertEqual(configs, [("По умолчанию", 16, 0), ("Без похожих символов", 24, 1)])
        types = self.db.execute(
            "SELECT code FROM character_types ORDER BY type_id"
        ).fetchall()
        self.assertEqual(types, [("lowercase",), ("uppercase",), ("digits",), ("symbols",)])
        selections = self.db.execute(
            "SELECT c.name, t.code FROM config_character_types AS ct "
            "JOIN generator_configs AS c ON c.config_id = ct.config_id "
            "JOIN character_types AS t ON t.type_id = ct.type_id"
        ).fetchall()
        self.assertEqual(len(selections), 7)
        self.assertEqual(
            {code for name, code in selections if name == "По умолчанию"},
            {"lowercase", "uppercase", "digits", "symbols"},
        )
        columns = [
            row[1]
            for (table,) in self.db.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
            )
            for row in self.db.execute(f"PRAGMA table_info({table})")
        ]
        self.assertFalse(any("password" in column.lower() and column != "password_length" for column in columns))

    def test_integrity_and_constraints(self):
        self.assertEqual(self.db.execute("PRAGMA foreign_keys").fetchone(), (1,))
        self.assertEqual(self.db.execute("PRAGMA integrity_check").fetchone(), ("ok",))
        self.assertEqual(self.db.execute("PRAGMA foreign_key_check").fetchall(), [])
        for length in (5, 129):
            with self.assertRaises(sqlite3.IntegrityError):
                self.db.execute(
                    "INSERT INTO generator_configs (name, password_length) VALUES (?, ?)",
                    (f"bad-{length}", length),
                )
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute(
                "INSERT INTO generator_configs (name, exclude_similar) VALUES ('bad-flag', 2)"
            )
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO character_types (code, display_name) VALUES ('other', 'Иное')")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO config_character_types VALUES (1, 1)")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO config_character_types VALUES (999, 1)")

    def test_deletion_cascades_only_to_links(self):
        self.db.execute("DELETE FROM generator_configs WHERE config_id = 1")
        self.assertEqual(self.db.execute("SELECT count(*) FROM config_character_types").fetchone(), (3,))
        self.assertEqual(self.db.execute("SELECT count(*) FROM character_types").fetchone(), (4,))
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("DELETE FROM character_types WHERE code = 'lowercase'")

    def test_explicit_indexes_exist(self):
        indexes = {
            row[0]
            for row in self.db.execute(
                "SELECT name FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_%'"
            )
        }
        self.assertIn("idx_generator_configs_created_at", indexes)
        self.assertIn("idx_config_character_types_type_id", indexes)


if __name__ == "__main__":
    unittest.main()
