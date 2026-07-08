import Foundation

public struct Action: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var description: String
    public var iconName: String?
    public var enabled: Bool

    public var acceptedExtensions: [String]
    public var acceptedUTIs: [String]

    public var executablePath: String
    public var argumentsTemplate: [String]

    public var workingDirectoryTemplate: String?
    public var outputPathTemplate: String?

    public var requiresConfirmation: Bool
    public var timeoutSeconds: Int

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        iconName: String? = nil,
        enabled: Bool = true,
        acceptedExtensions: [String] = [],
        acceptedUTIs: [String] = [],
        executablePath: String,
        argumentsTemplate: [String] = [],
        workingDirectoryTemplate: String? = nil,
        outputPathTemplate: String? = nil,
        requiresConfirmation: Bool = false,
        timeoutSeconds: Int = 30,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.iconName = iconName
        self.enabled = enabled
        self.acceptedExtensions = acceptedExtensions
        self.acceptedUTIs = acceptedUTIs
        self.executablePath = executablePath
        self.argumentsTemplate = argumentsTemplate
        self.workingDirectoryTemplate = workingDirectoryTemplate
        self.outputPathTemplate = outputPathTemplate
        self.requiresConfirmation = requiresConfirmation
        self.timeoutSeconds = timeoutSeconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
