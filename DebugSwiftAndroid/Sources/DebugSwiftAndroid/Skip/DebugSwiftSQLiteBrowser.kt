package debug.swift.android

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteException
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Read/write SQLite browser used for SQLite and registered Room database files. */
object DebugSwiftDatabaseBrowser {
    private val roomDatabaseNames = linkedSetOf<String>()

    fun registerRoomDatabase(databaseName: String) {
        if (databaseName.isNotBlank()) roomDatabaseNames.add(databaseName)
    }

    fun databaseNames(context: Context): List<String> =
        (context.databaseList().toList() + roomDatabaseNames).distinct().sorted()

    fun tables(context: Context, databaseName: String): List<String> = open(context, databaseName).use { database ->
        database.rawQuery("SELECT name FROM sqlite_master WHERE type IN ('table','view') ORDER BY name", null).use { cursor ->
            buildList { while (cursor.moveToNext()) add(cursor.getString(0)) }
        }
    }

    fun query(context: Context, databaseName: String, sql: String): String {
        if (databaseName.isBlank() || sql.isBlank()) return "Enter a database name and SQL statement."
        return try {
            open(context, databaseName).use { database ->
                val statement = sql.trim()
                if (statement.startsWith("SELECT", ignoreCase = true) || statement.startsWith("PRAGMA", ignoreCase = true) || statement.startsWith("EXPLAIN", ignoreCase = true)) {
                    database.rawQuery(statement, null).use { cursor -> cursorAsJson(cursor) }
                } else {
                    database.execSQL(statement)
                    "SQL statement executed.\n\nTables:\n${tables(context, databaseName).joinToString("\n")}"
                }
            }
        } catch (error: SQLiteException) {
            "SQLite error: ${error.message}"
        } catch (error: IllegalArgumentException) {
            "Invalid query: ${error.message}"
        }
    }

    private fun open(context: Context, name: String): SQLiteDatabase {
        val file = File(name).takeIf { it.isAbsolute } ?: context.getDatabasePath(name)
        if (!file.exists()) throw SQLiteException("Database not found: $name")
        return SQLiteDatabase.openDatabase(file.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
    }

    private fun cursorAsJson(cursor: android.database.Cursor): String {
        val rows = JSONArray()
        var count = 0
        while (cursor.moveToNext() && count < 250) {
            val row = JSONObject()
            for (column in cursor.columnNames.indices) {
                row.put(cursor.getColumnName(column), cursor.getString(column))
            }
            rows.put(row)
            count++
        }
        return "Rows: $count${if (cursor.count > count) " (limited to 250)" else ""}\n" + rows.toString(2)
    }
}

/** Host apps register Realm-specific projections so model and relationship metadata stays typed. */
object DebugSwiftRealmRegistry {
    private val providers = linkedMapOf<String, () -> String>()

    fun register(name: String, snapshotProvider: () -> String) {
        synchronized(providers) { providers[name] = snapshotProvider }
    }

    fun snapshot(): String = synchronized(providers) {
        providers.entries.joinToString("\n\n") { (name, provider) ->
            "$name\n${runCatching(provider).getOrElse { "Provider failed: ${it.message}" }}"
        }.ifEmpty { "No Realm provider registered. Register the host Realm schema through DebugSwiftRealmRegistry." }
    }
}
