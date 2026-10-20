package debug.swift.android

import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.security.keystore.KeyInfo
import android.webkit.CookieManager
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.KeyFactory
import java.security.KeyStore
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory

/**
 * Structured reads for the Resources screens: files, preferences, databases, Keystore aliases and
 * cookies. Each operation takes a JSON object and answers a JSON object, so the Swift screens can
 * render lists and forms instead of parsing text. Writes reuse the existing `perform` actions.
 */
object DebugSwiftResourceAPI {
    private const val PREVIEW_LIMIT_BYTES = 1_000_000L
    private const val PREVIEW_CHARACTERS = 64_000
    private const val ROW_LIMIT = 500

    @JvmStatic
    fun handle(operation: String, arguments: String): String {
        val context = AndroidDebugTools.contextOrNull()
            ?: return failure("Android runtime has not been installed.").toString()
        val args = runCatching { JSONObject(arguments) }.getOrDefault(JSONObject())
        return try {
            when (operation) {
                "files.list" -> filesList(context, args.optString("path"))
                "files.read" -> filesRead(context, args.optString("path"))
                "files.delete" -> filesDelete(context, args.optString("path"))
                "prefs.list" -> prefsList(context)
                "keystore.list" -> keystoreList()
                "db.list" -> dbList(context)
                "db.tables" -> dbTables(context, args.optString("db"))
                "db.rows" -> dbRows(context, args.optString("db"), args.optString("table"), args.optInt("offset"))
                "db.query" -> dbQuery(context, args.optString("db"), args.optString("sql"))
                "cookies.list" -> cookiesList()
                else -> failure("Unknown resource operation: $operation")
            }.toString()
        } catch (exception: Exception) {
            failure(exception.message ?: exception.javaClass.simpleName).toString()
        }
    }

    private fun failure(message: String) = JSONObject().put("error", message)

    // MARK: Files

    private fun root(context: Context, name: String): File? = when (name) {
        "files" -> context.filesDir
        "cache" -> context.cacheDir
        "databases" -> File(context.applicationInfo.dataDir, "databases")
        else -> null
    }?.canonicalFile

    /** Resolves "files/sub/dir" inside the three app-private roots, refusing anything outside them. */
    private fun resolve(context: Context, path: String): File? {
        val normalized = path.trim().trim('/')
        val root = root(context, normalized.substringBefore('/')) ?: return null
        val target = File(root, normalized.substringAfter('/', "")).canonicalFile
        return target.takeIf { it == root || it.path.startsWith(root.path + File.separator) }
    }

    private fun filesList(context: Context, path: String): JSONObject {
        val entries = JSONArray()
        if (path.isBlank()) {
            listOf("files", "cache", "databases").forEach { name ->
                entries.put(JSONObject().put("name", name).put("isDirectory", true).put("size", 0L).put("modified", 0L))
            }
            return JSONObject().put("path", "").put("entries", entries)
        }
        val directory = resolve(context, path) ?: return failure("The file browser is limited to the app's files, cache and databases.")
        if (!directory.isDirectory) return failure("Not a directory: $path")
        directory.listFiles().orEmpty()
            .sortedWith(compareBy<File> { !it.isDirectory }.thenBy { it.name.lowercase() })
            .take(500)
            .forEach { file ->
                entries.put(
                    JSONObject().put("name", file.name).put("isDirectory", file.isDirectory)
                        .put("size", if (file.isFile) file.length() else 0L).put("modified", file.lastModified())
                )
            }
        return JSONObject().put("path", path.trim().trim('/')).put("entries", entries)
    }

    private fun filesRead(context: Context, path: String): JSONObject {
        val file = resolve(context, path)?.takeIf { it.isFile } ?: return failure("File not found: $path")
        val result = JSONObject().put("path", path).put("size", file.length())
        if (file.length() > PREVIEW_LIMIT_BYTES) return result.put("isText", false).put("note", "Preview is limited to 1 MB.")
        val bytes = file.readBytes()
        val binary = bytes.take(8_000).any { it.toInt() == 0 }
        if (binary) return result.put("isText", false).put("note", "Binary file, no text preview.")
        return result.put("isText", true).put("text", String(bytes, Charsets.UTF_8).take(PREVIEW_CHARACTERS))
    }

    private fun filesDelete(context: Context, path: String): JSONObject {
        val file = resolve(context, path) ?: return failure("Path is outside the app's private storage.")
        if (path.trim().trim('/').let { !it.contains('/') }) return failure("Cannot delete a storage root.")
        if (!file.exists()) return failure("Path not found: $path")
        val deleted = if (file.isDirectory) file.deleteRecursively() else file.delete()
        return JSONObject().put("ok", deleted).put("message", if (deleted) "Deleted ${file.name}." else "Could not delete ${file.name}.")
    }

    // MARK: Preferences

    private fun prefsList(context: Context): JSONObject {
        val stores = JSONArray()
        AndroidDebugTools.preferenceStoreNames(context).forEach { name ->
            val values = JSONArray()
            context.getSharedPreferences(name, Context.MODE_PRIVATE).all.entries.sortedBy { it.key }.forEach { entry ->
                values.put(
                    JSONObject().put("key", entry.key).put("type", typeName(entry.value))
                        .put("value", when (val v = entry.value) { is Set<*> -> v.joinToString(","); else -> v.toString() })
                )
            }
            stores.put(JSONObject().put("name", name).put("values", values))
        }
        return JSONObject().put("stores", stores)
    }

    private fun typeName(value: Any?): String = when (value) {
        is Boolean -> "Boolean"
        is Int -> "Int"
        is Long -> "Long"
        is Float -> "Float"
        is Set<*> -> "Set"
        else -> "String"
    }

    // MARK: Keystore

    private fun keystoreList(): JSONObject {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val aliases = JSONArray()
        store.aliases().toList().sorted().forEach { alias ->
            val info = JSONObject().put("alias", alias)
            runCatching {
                val key = store.getKey(alias, null)
                info.put("algorithm", key?.algorithm ?: "")
                val keyInfo = when (key) {
                    is SecretKey -> SecretKeyFactory.getInstance(key.algorithm, "AndroidKeyStore").getKeySpec(key, KeyInfo::class.java) as KeyInfo
                    null -> null
                    else -> KeyFactory.getInstance(key.algorithm, "AndroidKeyStore").getKeySpec(key, KeyInfo::class.java)
                }
                if (keyInfo != null) {
                    info.put("size", keyInfo.keySize)
                    info.put("insideSecureHardware", keyInfo.isInsideSecureHardware)
                    info.put("requiresUserAuthentication", keyInfo.isUserAuthenticationRequired)
                }
            }
            aliases.put(info)
        }
        return JSONObject().put("aliases", aliases)
    }

    // MARK: Databases

    private fun dbList(context: Context): JSONObject {
        val databases = JSONArray()
        DebugSwiftDatabaseBrowser.databaseNames(context)
            .filterNot { name -> listOf("-journal", "-wal", "-shm").any(name::endsWith) }
            .forEach { name ->
            val file = context.getDatabasePath(name)
            databases.put(JSONObject().put("name", name).put("size", if (file.exists()) file.length() else 0L))
        }
        return JSONObject().put("databases", databases)
    }

    private fun open(context: Context, name: String): SQLiteDatabase {
        val file = File(name).takeIf { it.isAbsolute } ?: context.getDatabasePath(name)
        if (!file.exists()) throw IllegalArgumentException("Database not found: $name")
        return SQLiteDatabase.openDatabase(file.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
    }

    private fun quoted(identifier: String) = "\"" + identifier.replace("\"", "\"\"") + "\""

    private fun dbTables(context: Context, name: String): JSONObject = open(context, name).use { database ->
        val tables = JSONArray()
        DebugSwiftDatabaseBrowser.tables(context, name).forEach { table ->
            val count = runCatching {
                database.rawQuery("SELECT COUNT(*) FROM ${quoted(table)}", null).use { if (it.moveToFirst()) it.getLong(0) else 0L }
            }.getOrDefault(-1L)
            tables.put(JSONObject().put("name", table).put("rows", count))
        }
        JSONObject().put("db", name).put("tables", tables)
    }

    private fun dbRows(context: Context, name: String, table: String, offset: Int): JSONObject = open(context, name).use { database ->
        val total = database.rawQuery("SELECT COUNT(*) FROM ${quoted(table)}", null).use { if (it.moveToFirst()) it.getLong(0) else 0L }
        database.rawQuery("SELECT * FROM ${quoted(table)} LIMIT $ROW_LIMIT OFFSET ${offset.coerceAtLeast(0)}", null).use { cursor ->
            tableJSON(cursor).put("total", total).put("offset", offset.coerceAtLeast(0))
        }
    }

    private fun dbQuery(context: Context, name: String, sql: String): JSONObject {
        val statement = sql.trim()
        if (statement.isEmpty()) return failure("Enter a SQL statement.")
        return open(context, name).use { database ->
            val readOnly = listOf("SELECT", "PRAGMA", "EXPLAIN", "WITH").any { statement.startsWith(it, ignoreCase = true) }
            if (readOnly) {
                database.rawQuery(statement, null).use { cursor -> tableJSON(cursor) }
            } else {
                database.execSQL(statement)
                JSONObject().put("columns", JSONArray()).put("rows", JSONArray()).put("message", "SQL statement executed.")
            }
        }
    }

    private fun tableJSON(cursor: Cursor): JSONObject {
        val columns = JSONArray(cursor.columnNames.toList())
        val rows = JSONArray()
        var count = 0
        while (cursor.moveToNext() && count < ROW_LIMIT) {
            val row = JSONArray()
            for (column in 0 until cursor.columnCount) {
                row.put(
                    when (cursor.getType(column)) {
                        Cursor.FIELD_TYPE_NULL -> JSONObject.NULL
                        Cursor.FIELD_TYPE_BLOB -> "(blob, ${cursor.getBlob(column).size} bytes)"
                        else -> cursor.getString(column)
                    }
                )
            }
            rows.put(row)
            count++
        }
        return JSONObject().put("columns", columns).put("rows", rows)
    }

    // MARK: Cookies

    private fun cookiesList(): JSONObject {
        val hosts = JSONArray()
        AndroidDebugTools.webViewHostNames().forEach { host ->
            val raw = CookieManager.getInstance().getCookie("https://$host") ?: return@forEach
            val cookies = JSONArray()
            raw.split(';').map { it.trim() }.filter { it.isNotEmpty() }.forEach { pair ->
                cookies.put(JSONObject().put("name", pair.substringBefore('=')).put("value", pair.substringAfter('=', "")))
            }
            hosts.put(JSONObject().put("host", host).put("cookies", cookies))
        }
        return JSONObject().put("hosts", hosts)
    }
}
