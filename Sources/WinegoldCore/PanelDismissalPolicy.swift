public enum PanelDismissalPolicy {
    public static func allowsAutomaticDismissal(
        staysOpen: Bool,
        isModalInteractionActive: Bool,
        isVisible: Bool,
        isAnimatingOut: Bool,
        hasActiveFileDrag: Bool
    ) -> Bool {
        !staysOpen
            && !isModalInteractionActive
            && isVisible
            && !isAnimatingOut
            && !hasActiveFileDrag
    }
}
