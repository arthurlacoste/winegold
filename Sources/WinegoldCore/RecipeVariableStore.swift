import Foundation
import CSQLite

public struct RecipeVariableStore: RecipeVariableStoreProtocol {
    public let db: Database

    public init(db: Database) {
        self.db = db
    }

    public func readOverride(externalID: String, variableName: String) -> String? {
        guard let stmt = try? db.prepare("SELECT value FROM recipe_variable_overrides WHERE external_id=? AND variable_name=?") else { return nil }
        stmt.bindText(externalID, at: 1)
        stmt.bindText(variableName, at: 2)
        guard stmt.step() else { return nil }
        let value = stmt.columnText(at: 0)
        return value.isEmpty ? nil : value
    }

    public func writeOverride(externalID: String, variableName: String, value: String) {
        guard let stmt = try? db.prepare("""
            INSERT INTO recipe_variable_overrides (external_id, variable_name, value)
            VALUES (?, ?, ?)
            ON CONFLICT(external_id, variable_name) DO UPDATE SET value=excluded.value
        """) else { return }
        stmt.bindText(externalID, at: 1)
        stmt.bindText(variableName, at: 2)
        stmt.bindText(value, at: 3)
        _ = stmt.step()
    }

    public func deleteOverride(externalID: String, variableName: String) {
        guard let stmt = try? db.prepare("DELETE FROM recipe_variable_overrides WHERE external_id=? AND variable_name=?") else { return }
        stmt.bindText(externalID, at: 1)
        stmt.bindText(variableName, at: 2)
        _ = stmt.step()
    }

    public func consentStatus(key: String, externalID: String) -> Bool {
        guard let stmt = try? db.prepare("SELECT 1 FROM recipe_variable_consent WHERE key=? AND external_id=?") else { return false }
        stmt.bindText(key, at: 1)
        stmt.bindText(externalID, at: 2)
        return stmt.step()
    }

    public func grantConsent(key: String, externalID: String) {
        guard let stmt = try? db.prepare("""
            INSERT OR IGNORE INTO recipe_variable_consent (key, external_id)
            VALUES (?, ?)
        """) else { return }
        stmt.bindText(key, at: 1)
        stmt.bindText(externalID, at: 2)
        _ = stmt.step()
    }

    public func revokeConsent(key: String, externalID: String) {
        guard let stmt = try? db.prepare("DELETE FROM recipe_variable_consent WHERE key=? AND external_id=?") else { return }
        stmt.bindText(key, at: 1)
        stmt.bindText(externalID, at: 2)
        _ = stmt.step()
    }

    public func needsConsentWarning(key: String, newExternalID: String) -> Bool {
        guard let stmt = try? db.prepare("SELECT COUNT(*) FROM recipe_variable_consent WHERE key=? AND external_id!=?") else { return false }
        stmt.bindText(key, at: 1)
        stmt.bindText(newExternalID, at: 2)
        guard stmt.step() else { return false }
        return stmt.columnInt(at: 0) > 0 && !consentStatus(key: key, externalID: newExternalID)
    }

    public func savePrivateSecret(externalID: String, variableName: String, value: String, keychainStore: KeychainSecretStoreProtocol) {
        let storageKey = RecipeVariableResolver.privateSecretStorageKey(variable: variableName, externalID: externalID)
        keychainStore.write(key: storageKey, value: value)
    }

    public func saveSharedSecret(key: String, externalID: String, value: String, keychainStore: KeychainSecretStoreProtocol) {
        keychainStore.write(key: RecipeVariableResolver.sharedSecretStorageKey(key), value: value)
        grantConsent(key: key, externalID: externalID)
    }
}

public struct RecipeConsentManager {
    private let variableStore: RecipeVariableStoreProtocol
    private let keychainStore: KeychainSecretStoreProtocol

    public init(variableStore: RecipeVariableStoreProtocol, keychainStore: KeychainSecretStoreProtocol) {
        self.variableStore = variableStore
        self.keychainStore = keychainStore
    }

    public func consentWarnings(variables: [RecipeVariable], externalID: String) -> [String: String] {
        var warnings: [String: String] = [:]
        let existingKeys = Set(keychainStore.listKeys())
        for variable in variables where variable.secret {
            guard let key = variable.key else { continue }
            let storageKey = RecipeVariableResolver.secretStorageKey(variable: variable.name, externalID: externalID, key: key)
            if existingKeys.contains(storageKey) && !variableStore.consentStatus(key: key, externalID: externalID) {
                warnings[variable.name] = "This recipe requests access to your saved \"\(variable.label)\"."
            }
        }
        return warnings
    }
}
