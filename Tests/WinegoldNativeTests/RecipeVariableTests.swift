import XCTest
@testable import WinegoldCore

final class RecipeVariableTests: XCTestCase {

    // MARK: - Parsing

    func testParserReadsVariablesWithAllProperties() throws {
        let text = """
        name: Upload
        trigger: extension in {"jpg"}
        variables:
          ENDPOINT:
            label: Upload endpoint
            default: https://example.com/api.php
          TOKEN:
            label: Service token
            secret: true
            required: true
            key: upload-service.token
          ORG:
            label: Organization
        cmd:
          exec: 'echo $TOKEN'
        """
        let doc = try RecipeParser().parse(text: text)
        let variables = try XCTUnwrap(doc.variables)
        XCTAssertEqual(variables.count, 3)

        XCTAssertEqual(variables[0].name, "ENDPOINT")
        XCTAssertEqual(variables[0].label, "Upload endpoint")
        XCTAssertFalse(variables[0].secret)
        XCTAssertFalse(variables[0].required)
        XCTAssertEqual(variables[0].defaultValue, "https://example.com/api.php")
        XCTAssertNil(variables[0].key)

        XCTAssertEqual(variables[1].name, "TOKEN")
        XCTAssertEqual(variables[1].label, "Service token")
        XCTAssertTrue(variables[1].secret)
        XCTAssertTrue(variables[1].required)
        XCTAssertEqual(variables[1].key, "upload-service.token")

        XCTAssertEqual(variables[2].name, "ORG")
        XCTAssertEqual(variables[2].label, "Organization")
    }

    func testParserReadsEmptyVariablesSection() throws {
        let text = """
        name: Empty
        trigger: extension in {"txt"}
        cmd:
          exec: 'echo hi'
        """
        let doc = try RecipeParser().parse(text: text)
        XCTAssertNil(doc.variables)
    }

    func testParserSkipsNonVariableSectionsBetweenVariables() throws {
        let text = """
        name: Test
        trigger: extension in {"txt"}
        variables:
          A:
            label: Alpha
          B:
            label: Beta
            secret: true
        cmd:
          exec: 'echo $A'
        """
        let doc = try RecipeParser().parse(text: text)
        let variables = try XCTUnwrap(doc.variables)
        XCTAssertEqual(variables.count, 2)
        XCTAssertEqual(variables[0].name, "A")
        XCTAssertEqual(variables[1].name, "B")
        XCTAssertTrue(variables[1].secret)
    }

    func testDerivedLabelFromName() {
        XCTAssertEqual(RecipeVariable.derivedLabel(from: "UPLOAD_TOKEN"), "Upload Token")
        XCTAssertEqual(RecipeVariable.derivedLabel(from: "api-key"), "Api Key")
        XCTAssertEqual(RecipeVariable.derivedLabel(from: "URL"), "Url")
    }

    // MARK: - Variable resolution precedence (non-secret)

    func testNonSecretResolutionSQLiteOverrideFirst() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)
        store.writeOverride(externalID: "r1", variableName: "ENDPOINT", value: "from-sqlite")

        let resolver = RecipeVariableResolver(variableStore: store, keychainStore: NullKeychainStore())
        let vars = [RecipeVariable(name: "ENDPOINT", defaultValue: "from-yaml")]
        let result = resolver.resolve(variables: vars, externalID: "r1", appEnvironment: ["ENDPOINT": "from-env"])

        XCTAssertEqual(result["ENDPOINT"], "from-sqlite")
    }

    func testNonSecretResolutionFallsToEnv() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)

        let resolver = RecipeVariableResolver(variableStore: store, keychainStore: NullKeychainStore())
        let vars = [RecipeVariable(name: "ENDPOINT", defaultValue: "from-yaml")]
        let result = resolver.resolve(variables: vars, externalID: "r1", appEnvironment: ["ENDPOINT": "from-env"])

        XCTAssertEqual(result["ENDPOINT"], "from-env")
    }

    func testNonSecretResolutionFallsToYAMLDefault() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)

        let resolver = RecipeVariableResolver(variableStore: store, keychainStore: NullKeychainStore())
        let vars = [RecipeVariable(name: "ENDPOINT", defaultValue: "from-yaml")]
        let result = resolver.resolve(variables: vars, externalID: "r1", appEnvironment: [:])

        XCTAssertEqual(result["ENDPOINT"], "from-yaml")
    }

    func testNonSecretResolutionReturnsNilWhenMissing() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)

        let resolver = RecipeVariableResolver(variableStore: store, keychainStore: NullKeychainStore())
        let vars = [RecipeVariable(name: "ENDPOINT")]
        let result = resolver.resolve(variables: vars, externalID: "r1", appEnvironment: [:])

        XCTAssertNil(result["ENDPOINT"])
    }

    // MARK: - Variable resolution precedence (secret)

    func testSecretResolutionKeychainFirst() throws {
        let keychain = InMemoryKeychainStore()
        keychain.write(key: RecipeVariableResolver.privateSecretStorageKey(variable: "TOKEN", externalID: "r1"), value: "from-keychain")
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)

        let resolver = RecipeVariableResolver(variableStore: store, keychainStore: keychain)
        let vars = [RecipeVariable(name: "TOKEN", secret: true)]
        let result = resolver.resolve(variables: vars, externalID: "r1", appEnvironment: ["TOKEN": "from-env"])

        XCTAssertEqual(result["TOKEN"], "from-keychain")
    }

    func testSecretResolutionFallsToEnv() throws {
        let keychain = InMemoryKeychainStore()
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)

        let resolver = RecipeVariableResolver(variableStore: store, keychainStore: keychain)
        let vars = [RecipeVariable(name: "TOKEN", secret: true)]
        let result = resolver.resolve(variables: vars, externalID: "r1", appEnvironment: ["TOKEN": "from-env"])

        XCTAssertEqual(result["TOKEN"], "from-env")
    }

    func testSecretResolutionReturnsNilWhenMissing() throws {
        let keychain = InMemoryKeychainStore()
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)

        let resolver = RecipeVariableResolver(variableStore: store, keychainStore: keychain)
        let vars = [RecipeVariable(name: "TOKEN", secret: true)]
        let result = resolver.resolve(variables: vars, externalID: "r1", appEnvironment: [:])

        XCTAssertNil(result["TOKEN"])
    }

    // MARK: - Setup state

    func testSetupStatusReadyWhenAllRequiredMet() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)
        store.writeOverride(externalID: "r1", variableName: "TOKEN", value: "value")

        let resolver = RecipeVariableResolver(variableStore: store, keychainStore: NullKeychainStore())
        let vars = [RecipeVariable(name: "TOKEN", required: true)]
        let status = resolver.setupStatus(variables: vars, externalID: "r1", appEnvironment: [:])

        XCTAssertEqual(status, .ready)
    }

    func testSetupStatusNeedsSetupWhenRequiredMissing() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)

        let resolver = RecipeVariableResolver(variableStore: store, keychainStore: NullKeychainStore())
        let vars = [RecipeVariable(name: "TOKEN", required: true)]
        let status = resolver.setupStatus(variables: vars, externalID: "r1", appEnvironment: [:])

        if case let .needsSetup(missing) = status {
            XCTAssertEqual(missing.count, 1)
            XCTAssertEqual(missing[0].name, "TOKEN")
        } else {
            XCTFail("Expected needsSetup")
        }
    }

    func testSetupStatusReadyWhenNoVariables() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)

        let resolver = RecipeVariableResolver(variableStore: store, keychainStore: NullKeychainStore())
        let status = resolver.setupStatus(variables: [], externalID: "r1", appEnvironment: [:])

        XCTAssertEqual(status, .ready)
    }

    // MARK: - Environment injection

    func testEnvironmentInjectionViaCommandExecutionRequest() {
        var request = CommandExecutionRequest(
            executablePath: "/bin/echo",
            arguments: ["hello"],
            environment: ["MY_VAR": "test_value"]
        )
        var env = ProcessInfo.processInfo.environment
        env.merge(request.environment ?? [:]) { _, new in new }
        request.environment = env

        XCTAssertEqual(request.environment?["MY_VAR"], "test_value")
    }

    func testVariableResolutionProvidesEnvironmentDictionary() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)
        store.writeOverride(externalID: "r1", variableName: "API_URL", value: "https://api.example.com")

        let keychain = InMemoryKeychainStore()
        keychain.write(key: RecipeVariableResolver.privateSecretStorageKey(variable: "API_KEY", externalID: "r1"), value: "secret123")

        let resolver = RecipeVariableResolver(variableStore: store, keychainStore: keychain)
        let vars = [
            RecipeVariable(name: "API_URL", defaultValue: "https://default.com"),
            RecipeVariable(name: "API_KEY", secret: true),
            RecipeVariable(name: "DEBUG", defaultValue: "false")
        ]
        let env = resolver.resolve(variables: vars, externalID: "r1", appEnvironment: [:])

        XCTAssertEqual(env["API_URL"], "https://api.example.com")
        XCTAssertEqual(env["API_KEY"], "secret123")
        XCTAssertEqual(env["DEBUG"], "false")
    }

    // MARK: - Secret redaction

    func testRedactorReplacesSecretValues() {
        let redactor = SecretRedactor()
        let text = "Authorization: Bearer secret123abc and secret123abc again"
        let result = redactor.redact(text, secretValues: ["secret123abc"])

        XCTAssertFalse(result.contains("secret123abc"))
        XCTAssertTrue(result.contains("********"))
    }

    func testRedactorSkipsShortValues() {
        let redactor = SecretRedactor()
        let text = "value is ab"
        let result = redactor.redact(text, secretValues: ["ab"])

        XCTAssertEqual(result, "value is ab")
    }

    func testRedactorSkipsEmptyValues() {
        let redactor = SecretRedactor()
        let text = "nothing to see"
        let result = redactor.redact(text, secretValues: [""])

        XCTAssertEqual(result, "nothing to see")
    }

    func testRedactorSortsByLengthDescending() {
        let redactor = SecretRedactor()
        let text = "token: mylongtokenvalue"
        let result = redactor.redact(text, secretValues: ["mylongtokenvalue", "mylong"])

        XCTAssertTrue(result.contains("*"))
        XCTAssertFalse(result.contains("mylong"))
    }

    func testRedactCommandInRequest() {
        let redactor = SecretRedactor()
        let request = CommandExecutionRequest(
            executablePath: "/bin/curl",
            arguments: ["-H", "Bearer secret123"]
        )
        let redacted = redactor.redactCommand(request, secretValues: ["secret123"])

        XCTAssertEqual(redacted.arguments[1], "Bearer ********")
        XCTAssertEqual(redacted.executablePath, "/bin/curl")
    }

    // MARK: - Shared key consent

    func testConsentWarningForNewRecipeUsingExistingKey() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)
        let keychain = InMemoryKeychainStore()
        keychain.write(key: RecipeVariableResolver.sharedSecretStorageKey("openai.api-key"), value: "sk-existing")

        let manager = RecipeConsentManager(variableStore: store, keychainStore: keychain)
        let vars = [RecipeVariable(name: "OPENAI_API_KEY", secret: true, key: "openai.api-key")]
        let warnings = manager.consentWarnings(variables: vars, externalID: "recipe-new")

        XCTAssertEqual(warnings.count, 1)
        let msg = try XCTUnwrap(warnings["OPENAI_API_KEY"])
        XCTAssertTrue(msg.contains("Openai Api Key"), "Expected 'Openai Api Key' in: \(msg)")
    }

    func testNoConsentWarningWhenSameRecipeAlreadyConsented() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)
        store.grantConsent(key: "openai.api-key", externalID: "recipe-existing")
        let keychain = InMemoryKeychainStore()
        keychain.write(key: RecipeVariableResolver.sharedSecretStorageKey("openai.api-key"), value: "sk-existing")

        let manager = RecipeConsentManager(variableStore: store, keychainStore: keychain)
        let vars = [RecipeVariable(name: "OPENAI_API_KEY", secret: true, key: "openai.api-key")]
        let warnings = manager.consentWarnings(variables: vars, externalID: "recipe-existing")

        XCTAssertTrue(warnings.isEmpty)
    }

    func testNoConsentWarningWithoutKey() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)
        let keychain = InMemoryKeychainStore()
        keychain.write(key: "winegold.some-key", value: "val")

        let manager = RecipeConsentManager(variableStore: store, keychainStore: keychain)
        let vars = [RecipeVariable(name: "TOKEN", secret: true)]
        let warnings = manager.consentWarnings(variables: vars, externalID: "new-recipe")

        XCTAssertTrue(warnings.isEmpty)
    }

    func testNoConsentWarningWhenKeyNotInKeychain() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)
        let keychain = InMemoryKeychainStore()

        let manager = RecipeConsentManager(variableStore: store, keychainStore: keychain)
        let vars = [RecipeVariable(name: "OPENAI_API_KEY", secret: true, key: "openai.api-key")]
        let warnings = manager.consentWarnings(variables: vars, externalID: "recipe-new")

        XCTAssertTrue(warnings.isEmpty)
    }

    func testConsentGrantAndRevoke() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)

        XCTAssertFalse(store.consentStatus(key: "k", externalID: "r"))
        store.grantConsent(key: "k", externalID: "r")
        XCTAssertTrue(store.consentStatus(key: "k", externalID: "r"))
        store.revokeConsent(key: "k", externalID: "r")
        XCTAssertFalse(store.consentStatus(key: "k", externalID: "r"))
    }

    // MARK: - SQLite overrides

    func testOverrideWriteAndRead() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)

        XCTAssertNil(store.readOverride(externalID: "r1", variableName: "X"))
        store.writeOverride(externalID: "r1", variableName: "X", value: "hello")
        XCTAssertEqual(store.readOverride(externalID: "r1", variableName: "X"), "hello")
    }

    func testOverrideDelete() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)

        store.writeOverride(externalID: "r1", variableName: "X", value: "hello")
        store.deleteOverride(externalID: "r1", variableName: "X")
        XCTAssertNil(store.readOverride(externalID: "r1", variableName: "X"))
    }

    func testOverrideIsolationBetweenRecipes() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)

        store.writeOverride(externalID: "r1", variableName: "X", value: "one")
        store.writeOverride(externalID: "r2", variableName: "X", value: "two")
        XCTAssertEqual(store.readOverride(externalID: "r1", variableName: "X"), "one")
        XCTAssertEqual(store.readOverride(externalID: "r2", variableName: "X"), "two")
    }

    // MARK: - Export filtering

    func testExportFilterPreservesDeclarativeDefaults() throws {
        let doc = RecipeDocument(
            name: "Test",
            trigger: "extension in {\"txt\"}",
            command: "echo $TOKEN",
            variables: [
                RecipeVariable(name: "TOKEN", secret: true, required: true, defaultValue: "do-not-export", key: "my.key")
            ]
        )
        let filtered = RecipeVariableExportFilter().filterForExport(doc)
        let vars = try XCTUnwrap(filtered.variables)
        XCTAssertEqual(vars[0].defaultValue, "do-not-export")
        XCTAssertEqual(vars[0].key, "my.key")
        XCTAssertEqual(vars[0].name, "TOKEN")
    }

    func testExportFilterPreservesLabelsAndFlags() throws {
        let doc = RecipeDocument(
            name: "Test",
            trigger: "extension in {\"txt\"}",
            command: "echo $X",
            variables: [
                RecipeVariable(name: "X", label: "X label", secret: true, required: true, key: "x.key")
            ]
        )
        let filtered = RecipeVariableExportFilter().filterForExport(doc)
        let vars = try XCTUnwrap(filtered.variables)
        XCTAssertEqual(vars[0].label, "X label")
        XCTAssertTrue(vars[0].secret)
        XCTAssertTrue(vars[0].required)
    }

    // MARK: - Recipe variable local secret store integration

    func testLocalSecretStoreWriteAndRead() {
        let fixture = localSecretFixture()
        let store = LocalSecretStore(fileURL: fixture)
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }

        store.write(key: "token", value: "hello")
        XCTAssertEqual(store.read(key: "token"), "hello")
        let permissions = try? FileManager.default.attributesOfItem(atPath: fixture.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testLocalSecretStoreDelete() {
        let fixture = localSecretFixture()
        let store = LocalSecretStore(fileURL: fixture)
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }

        store.write(key: "token", value: "hello")
        store.delete(key: "token")
        XCTAssertNil(store.read(key: "token"))
    }

    func testLocalSecretStoreListKeys() {
        let fixture = localSecretFixture()
        let store = LocalSecretStore(fileURL: fixture)
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }

        store.write(key: "a", value: "one")
        store.write(key: "b", value: "two")
        let keys = store.listKeys()
        XCTAssertEqual(Set(keys), ["a", "b"])
    }

    private func localSecretFixture() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("winegold-secret-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("secrets.json")
    }

    // MARK: - Secret storage key format

    func testSecretStorageKeyFormat() {
        let key = RecipeVariableResolver.secretStorageKey(variable: "API_KEY", externalID: "winegold.upload")
        XCTAssertEqual(key, "winegold.recipe.winegold.upload.API_KEY")
    }

    func testSecretStorageKeyFormatWithSharedKey() {
        let key = RecipeVariableResolver.secretStorageKey(variable: "API_KEY", externalID: "winegold.upload", key: "openai.api-key")
        XCTAssertEqual(key, RecipeVariableResolver.sharedSecretStorageKey("openai.api-key"))
    }

    // MARK: - Shared key resolution

    func testSharedKeyResolutionFromKeychain() throws {
        let keychain = InMemoryKeychainStore()
        keychain.write(key: RecipeVariableResolver.sharedSecretStorageKey("openai.api-key"), value: "sk-shared")
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)

        store.grantConsent(key: "openai.api-key", externalID: "recipe-new")
        let resolver = RecipeVariableResolver(variableStore: store, keychainStore: keychain)
        let vars = [RecipeVariable(name: "OPENAI_API_KEY", secret: true, key: "openai.api-key")]
        let result = resolver.resolve(variables: vars, externalID: "recipe-new", appEnvironment: [:])

        XCTAssertEqual(result["OPENAI_API_KEY"], "sk-shared")
    }


    func testSharedKeyIsUnavailableWithoutConsent() throws {
        let keychain = InMemoryKeychainStore()
        keychain.write(key: RecipeVariableResolver.sharedSecretStorageKey("openai.api-key"), value: "sk-shared")
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)
        let resolver = RecipeVariableResolver(variableStore: store, keychainStore: keychain)
        let vars = [RecipeVariable(name: "OPENAI_API_KEY", secret: true, required: true, key: "openai.api-key")]

        XCTAssertNil(resolver.resolve(variables: vars, externalID: "recipe-new", appEnvironment: [:])["OPENAI_API_KEY"])
        XCTAssertEqual(resolver.setupStatus(variables: vars, externalID: "recipe-new", appEnvironment: [:]), .needsSetup(missing: vars))
    }

    func testSeparatePrivateSecretWinsWithoutSharedConsent() throws {
        let keychain = InMemoryKeychainStore()
        keychain.write(key: RecipeVariableResolver.sharedSecretStorageKey("openai.api-key"), value: "sk-shared")
        keychain.write(key: RecipeVariableResolver.privateSecretStorageKey(variable: "OPENAI_API_KEY", externalID: "recipe-new"), value: "sk-private")
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)
        let resolver = RecipeVariableResolver(variableStore: store, keychainStore: keychain)
        let vars = [RecipeVariable(name: "OPENAI_API_KEY", secret: true, key: "openai.api-key")]

        XCTAssertEqual(resolver.resolve(variables: vars, externalID: "recipe-new", appEnvironment: [:])["OPENAI_API_KEY"], "sk-private")
    }

    func testSharedKeyConsentDetectionFromKeychain() throws {
        let keychain = InMemoryKeychainStore()
        keychain.write(key: RecipeVariableResolver.sharedSecretStorageKey("openai.api-key"), value: "sk-shared")
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)

        let manager = RecipeConsentManager(variableStore: store, keychainStore: keychain)
        let vars = [RecipeVariable(name: "OPENAI_API_KEY", secret: true, key: "openai.api-key")]
        let warnings = manager.consentWarnings(variables: vars, externalID: "new-recipe")

        XCTAssertEqual(warnings.count, 1)
    }

    // MARK: - Environment injection during execution

    func testRecipeVariablesInjectedIntoExecutionEnvironment() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)
        store.writeOverride(externalID: "r1", variableName: "API_URL", value: "https://api.example.com")
        let keychain = InMemoryKeychainStore()
        keychain.write(key: RecipeVariableResolver.privateSecretStorageKey(variable: "API_KEY", externalID: "r1"), value: "secret123")

        let resolver = RecipeVariableResolver(variableStore: store, keychainStore: keychain)
        let vars = [
            RecipeVariable(name: "API_URL", defaultValue: "https://default.com"),
            RecipeVariable(name: "API_KEY", secret: true),
            RecipeVariable(name: "DEBUG", defaultValue: "false")
        ]
        let env = resolver.resolve(variables: vars, externalID: "r1", appEnvironment: [:])

        var request = CommandExecutionRequest(
            executablePath: "/bin/curl",
            arguments: ["-H", "Bearer $API_KEY"],
            environment: env
        )
        var processEnv = ProcessInfo.processInfo.environment
        processEnv.merge(request.environment ?? [:]) { _, new in new }
        request.environment = processEnv

        XCTAssertEqual(request.environment?["API_URL"], "https://api.example.com")
        XCTAssertEqual(request.environment?["API_KEY"], "secret123")
        XCTAssertEqual(request.environment?["DEBUG"], "false")
    }

    // MARK: - Secret values collection for redaction

    func testSecretValuesCollectionForRedaction() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)
        let keychain = InMemoryKeychainStore()
        keychain.write(key: RecipeVariableResolver.privateSecretStorageKey(variable: "TOKEN", externalID: "r1"), value: "my-secret-token")

        let resolver = RecipeVariableResolver(variableStore: store, keychainStore: keychain)
        let vars = [
            RecipeVariable(name: "TOKEN", secret: true),
            RecipeVariable(name: "ENDPOINT", defaultValue: "https://api.example.com")
        ]
        let secrets = resolver.secretValues(variables: vars, externalID: "r1", appEnvironment: [:])

        XCTAssertEqual(secrets.count, 1)
        XCTAssertEqual(secrets.first, "my-secret-token")
    }

    func testSecretValuesExcludesNonSecrets() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)
        let keychain = InMemoryKeychainStore()

        let resolver = RecipeVariableResolver(variableStore: store, keychainStore: keychain)
        let vars = [
            RecipeVariable(name: "ENDPOINT", defaultValue: "https://api.example.com"),
            RecipeVariable(name: "TOKEN", defaultValue: "not-secret")
        ]
        let secrets = resolver.secretValues(variables: vars, externalID: "r1", appEnvironment: [:])

        XCTAssertTrue(secrets.isEmpty)
    }

    // MARK: - Redaction in command execution output

    func testRedactionAppliedToCommandResultOutput() {
        let redactor = SecretRedactor()
        let secretValues = ["my-secret-api-key-12345"]

        let stdout = "Uploaded to https://api.example.com with key my-secret-api-key-12345"
        let stderr = "Error: Authorization failed my-secret-api-key-12345"

        let redactedStdout = redactor.redact(stdout, secretValues: secretValues)
        let redactedStderr = redactor.redact(stderr, secretValues: secretValues)

        XCTAssertFalse(redactedStdout.contains("my-secret-api-key-12345"))
        XCTAssertFalse(redactedStderr.contains("my-secret-api-key-12345"))
        XCTAssertTrue(redactedStdout.contains("********"))
        XCTAssertTrue(redactedStderr.contains("********"))
    }

    func testRedactionInLiveProgressOutput() {
        let redactor = SecretRedactor()
        let secretValues = ["sk-abc123def456"]

        let liveStdout = "Processing with key sk-abc123def456..."
        let redacted = redactor.redact(liveStdout, secretValues: secretValues)

        XCTAssertFalse(redacted.contains("sk-abc123def456"))
        XCTAssertTrue(redacted.contains("********"))
    }

    // MARK: - RecipeDocument round-trip with variables

    func testRecipeDocumentRoundTripWithVariables() throws {
        let root = temporaryDirectory()
        let url = root.appendingPathComponent("upload/upload.wg.yml")
        let store = RecipeFileStore(root: root)
        let doc = RecipeDocument(
            id: "winegold.upload",
            name: "Upload",
            trigger: "extension in {\"jpg\"}",
            command: "echo $TOKEN",
            variables: [
                RecipeVariable(name: "ENDPOINT", defaultValue: "https://api.example.com"),
                RecipeVariable(name: "TOKEN", secret: true, required: true, key: "upload.token")
            ]
        )
        _ = try store.write(doc, to: url)
        let content = try String(contentsOf: url)

        XCTAssertTrue(content.contains("variables:"))
        XCTAssertTrue(content.contains("ENDPOINT:"))
        XCTAssertTrue(content.contains("TOKEN:"))
        XCTAssertTrue(content.contains("secret: true"))
        XCTAssertTrue(content.contains("required: true"))

        let reparsed = try RecipeParser().parse(url: url)
        let variables = try XCTUnwrap(reparsed.document.variables)
        XCTAssertEqual(variables.count, 2)
        XCTAssertEqual(variables[0].name, "ENDPOINT")
        XCTAssertEqual(variables[0].defaultValue, "https://api.example.com")
        XCTAssertEqual(variables[1].name, "TOKEN")
        XCTAssertTrue(variables[1].secret)
        XCTAssertTrue(variables[1].required)
        XCTAssertEqual(variables[1].key, "upload.token")
    }

    // MARK: - Full YAML example from issue

    func testIssueExampleYAML() throws {
        let text = """
        variables:
          UPLOAD_ENDPOINT:
            label: Upload endpoint
            default: https://example.com/api.php

          UPLOAD_TOKEN:
            label: Service token
            secret: true
            required: true
            key: upload-service.token

        name: Upload image
        trigger: extension in {"jpg" "png"}
        cmd:
          exec: |
            curl -fsS \\
              -H "Authorization: Bearer $UPLOAD_TOKEN" \\
              -F "file=@{input}" \\
              "$UPLOAD_ENDPOINT?format=url"
        """
        let doc = try RecipeParser().parse(text: text)
        let variables = try XCTUnwrap(doc.variables)
        XCTAssertEqual(variables.count, 2)
        XCTAssertEqual(variables[0].name, "UPLOAD_ENDPOINT")
        XCTAssertEqual(variables[0].label, "Upload endpoint")
        XCTAssertEqual(variables[0].defaultValue, "https://example.com/api.php")
        XCTAssertFalse(variables[0].secret)
        XCTAssertFalse(variables[0].required)
        XCTAssertEqual(variables[1].name, "UPLOAD_TOKEN")
        XCTAssertEqual(variables[1].label, "Service token")
        XCTAssertTrue(variables[1].secret)
        XCTAssertTrue(variables[1].required)
        XCTAssertEqual(variables[1].key, "upload-service.token")
    }

    // MARK: - Incomplete required variable missing returns correct missing list

    func testSetupStatusListsAllMissingRequiredVariables() throws {
        let db = try inMemoryDB()
        let store = RecipeVariableStore(db: db)
        let resolver = RecipeVariableResolver(variableStore: store, keychainStore: NullKeychainStore())
        let vars = [
            RecipeVariable(name: "A", required: true),
            RecipeVariable(name: "B", required: true),
            RecipeVariable(name: "C", required: false)
        ]
        let status = resolver.setupStatus(variables: vars, externalID: "r1", appEnvironment: [:])

        if case let .needsSetup(missing) = status {
            XCTAssertEqual(missing.count, 2)
            XCTAssertEqual(missing.map(\.name).sorted(), ["A", "B"])
        } else {
            XCTFail("Expected needsSetup")
        }
    }

    func testCoordinatorReportsCommandAndVariableSetupBlockers() throws {
        let root = temporaryDirectory().appendingPathComponent("recipes")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let recipe = """
        id: winegold.setup-test
        name: Setup test
        trigger: extension in {"txt"}
        requires:
          commands:
            - winegold-command-that-does-not-exist
        variables:
          TOKEN:
            required: true
            secret: true
        cmd:
          exec: 'echo "$TOKEN"'
        """
        try recipe.write(to: root.appendingPathComponent("setup.wg.yml"), atomically: true, encoding: .utf8)
        let db = try inMemoryDB()
        let variableStore = RecipeVariableStore(db: db)
        let coordinator = RecipeCoordinator(
            root: root,
            db: db,
            variableStore: variableStore,
            keychainStore: InMemoryKeychainStore()
        )

        try coordinator.reconcile()
        let actionID = RecipeParser.runtimeUUID(for: "winegold.setup-test")
        let requirements = try XCTUnwrap(coordinator.setupRequirements(for: actionID))

        XCTAssertEqual(requirements.missingCommands, ["winegold-command-that-does-not-exist"])
        XCTAssertEqual(requirements.missingVariables.map(\.name), ["TOKEN"])
        XCTAssertEqual(try ActionStore(db: db).listNeedingSetup().map(\.id), [actionID])
    }

    // MARK: - Helpers

    private func inMemoryDB() throws -> Database {
        let url = temporaryDirectory().appendingPathComponent("test-\(UUID().uuidString).db")
        let db = try Database(path: url.path)
        try Migrations(db: db).run()
        return db
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private struct NullKeychainStore: KeychainSecretStoreProtocol {
    func read(key: String) -> String? { nil }
    func write(key: String, value: String) {}
    func delete(key: String) {}
    func listKeys() -> [String] { [] }
}

private final class InMemoryKeychainStore: KeychainSecretStoreProtocol {
    private var storage: [String: String] = [:]
    func read(key: String) -> String? { storage[key] }
    func write(key: String, value: String) { storage[key] = value }
    func delete(key: String) { storage.removeValue(forKey: key) }
    func listKeys() -> [String] { Array(storage.keys) }
}
