import os

/// Unified logging. Never log tokens, account identifiers or raw payloads.
public enum Log {
    public static let providers = Logger(subsystem: "app.aiquota", category: "providers")
    public static let store = Logger(subsystem: "app.aiquota", category: "store")
    public static let alerts = Logger(subsystem: "app.aiquota", category: "alerts")
    public static let integration = Logger(subsystem: "app.aiquota", category: "integration")
}
