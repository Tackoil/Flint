/// Build-time capabilities. Direct Swift builds retain all features unless an
/// explicit selection is supplied with FLINT_CUSTOM_FEATURES.
enum BuildFeatures {
    #if !FLINT_CUSTOM_FEATURES || FLINT_CALCULATOR
    static let calculator = true
    #else
    static let calculator = false
    #endif

    #if !FLINT_CUSTOM_FEATURES || FLINT_TIMESTAMPS
    static let timestamps = true
    #else
    static let timestamps = false
    #endif

    #if !FLINT_CUSTOM_FEATURES || FLINT_COLORS
    static let colors = true
    #else
    static let colors = false
    #endif

    #if !FLINT_CUSTOM_FEATURES || FLINT_NUMBER_BASES
    static let numberBases = true
    #else
    static let numberBases = false
    #endif

    #if !FLINT_CUSTOM_FEATURES || FLINT_QR
    static let qrCode = true
    #else
    static let qrCode = false
    #endif

    #if !FLINT_CUSTOM_FEATURES || FLINT_TRANSLATION
    static let translation = true
    #else
    static let translation = false
    #endif

    #if !FLINT_CUSTOM_FEATURES || FLINT_QUICK_LINKS
    static let quickLinks = true
    #else
    static let quickLinks = false
    #endif

    #if !FLINT_CUSTOM_FEATURES || FLINT_SCRIPTS
    static let scripts = true
    #else
    static let scripts = false
    #endif

    #if !FLINT_CUSTOM_FEATURES || FLINT_SYSTEM_ACTIONS
    static let systemActions = true
    #else
    static let systemActions = false
    #endif
}
