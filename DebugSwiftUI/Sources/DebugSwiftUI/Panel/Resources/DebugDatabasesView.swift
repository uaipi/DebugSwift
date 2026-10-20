import SwiftUI

/// The app's SQLite databases (Room databases are SQLite files too). Each opens to its tables.
struct DebugDatabasesView: View {
    let title: String
    @State var databases: [DebugDatabaseInfo] = []
    @State var failure = ""

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if databases.isEmpty && failure.isEmpty {
                Text(verbatim: "No databases found in this app.")
                    .foregroundColor(Color.secondary)
            }
            ForEach(databases) { database in
                NavigationLink {
                    DebugTablesView(database: database.name)
                } label: {
                    HStack {
                        Text(verbatim: database.name)
                        Spacer()
                        Text(verbatim: debugByteCount(database.size))
                            .font(.caption)
                            .foregroundColor(Color.secondary)
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: title))
        .onAppear { load() }
    }

    func load() {
        switch DebugResourceClient.fetch("db.list", as: DebugDatabaseListing.self) {
        case let .success(value):
            databases = value.databases
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}

struct DebugTablesView: View {
    let database: String
    @State var tables: [DebugTableInfo] = []
    @State var failure = ""

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            Section {
                NavigationLink {
                    DebugSQLConsoleView(database: database)
                } label: {
                    Text(verbatim: "SQL console").foregroundColor(Color.accentColor)
                }
            }
            Section("Tables") {
                ForEach(tables) { table in
                    NavigationLink {
                        DebugTableRowsView(database: database, table: table.name, offset: 0)
                    } label: {
                        HStack {
                            Text(verbatim: table.name)
                            Spacer()
                            Text(verbatim: table.rows >= 0 ? "\(table.rows) rows" : "")
                                .font(.caption)
                                .foregroundColor(Color.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: database))
        .onAppear { load() }
    }

    func load() {
        switch DebugResourceClient.fetch("db.tables", ["db": database], as: DebugTableListing.self) {
        case let .success(value):
            tables = value.tables
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}

/// Rows of one table, 500 at a time. Each row lists its columns under each other.
struct DebugTableRowsView: View {
    let database: String
    let table: String
    @State var offset: Int
    @State var data: DebugTableData? = nil
    @State var failure = ""

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if let data {
                Section {
                    Text(verbatim: "\(offset + 1)-\(offset + data.rows.count) of \(data.total ?? data.rows.count)")
                        .font(.caption)
                    if offset > 0 {
                        Button("Previous page") { move(by: -500) }
                    }
                    if offset + data.rows.count < (data.total ?? 0) {
                        Button("Next page") { move(by: 500) }
                    }
                }
                ForEach(0..<data.rows.count, id: \.self) { index in
                    DebugTableRowView(columns: data.columns, values: data.rows[index])
                }
            }
        }
        .navigationTitle(Text(verbatim: table))
        .onAppear { load() }
    }

    func move(by amount: Int) {
        offset = max(0, offset + amount)
        load()
    }

    func load() {
        let result = DebugResourceClient.fetch(
            "db.rows",
            ["db": database, "table": table, "offset": String(offset)],
            as: DebugTableData.self,
        )
        switch result {
        case let .success(value):
            data = value
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}

struct DebugTableRowView: View {
    let columns: [String]
    let values: [String?]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<columns.count, id: \.self) { index in
                HStack(alignment: .top) {
                    Text(verbatim: columns[index])
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                    Spacer()
                    Text(verbatim: index < values.count ? (values[index] ?? "NULL") : "")
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(4)
                }
            }
        }
    }
}

/// Runs a SQL statement against one database. Reads show their rows; anything else just runs.
struct DebugSQLConsoleView: View {
    let database: String
    @State var sql = ""
    @State var data: DebugTableData? = nil
    @State var message = ""

    var body: some View {
        List {
            Section("SQL") {
                TextField("SELECT * FROM table", text: $sql)
                Button("Run") { run() }
            }
            if !message.isEmpty {
                Section("Result") {
                    Text(verbatim: message).font(.caption)
                }
            }
            if let data {
                ForEach(0..<data.rows.count, id: \.self) { index in
                    DebugTableRowView(columns: data.columns, values: data.rows[index])
                }
            }
        }
        .navigationTitle("SQL console")
    }

    func run() {
        switch DebugResourceClient.fetch("db.query", ["db": database, "sql": sql], as: DebugTableData.self) {
        case let .success(value):
            data = value
            message = value.message ?? "\(value.rows.count) rows."
        case let .failure(error):
            data = nil
            message = error.message
        }
    }
}
