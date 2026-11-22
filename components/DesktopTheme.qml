import ".."

Theme {
    // Desktop light-mode surfaces use the same roles as the shared palette.
    colors: darkMode ? ({}) : ({
        panelSurface: "#e8ebf0",
        backgroundSurface: "#dde3eb",
        surfaceRaised: "#f2f4f7",
        surfaceHover: "#e0e6ee",
        surfaceSelected: "#d8e4f2",
        inputSurface: "#f9fafc",
        materialEdge: "#70465d73",
        outline: "#a9b5c4",
        separator: "#c9d2de",
        textPrimary: "#212934",
        textSecondary: "#465363",
        textMuted: "#586677",
        accent: "#315a89"
    })
}
