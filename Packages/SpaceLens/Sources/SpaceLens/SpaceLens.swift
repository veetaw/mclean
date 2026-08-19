/// Space Lens — PROMPT MASTER §5.1's "visualizzazione treemap interattiva
/// dello spazio disco" (interactive disk-usage treemap).
///
/// Strictly read-only and, per the product spec, "prevalentemente
/// UI/read-only": this module's job is to visualize where disk space goes,
/// not to classify or clean anything. It has no dependency on
/// `CoreScanEngine` or `SafetyRules` and performs no writes, moves, or
/// deletes anywhere.
///
/// ## Layers
/// - **Model** (`Model/`) — ``DirectoryNode``, a pure value-type size tree,
///   and ``DirectorySizeTreeBuilder``, the bounded, cancellable,
///   permission-error-tolerant filesystem walker that builds one.
/// - **Layout** (`Layout/`) — ``SquarifiedTreemapLayout``, a pure geometry
///   function (no SwiftUI dependency) implementing the standard squarified
///   treemap algorithm.
/// - **Views** (`Views/`) — ``SpaceLensView``, the public entry point (a
///   loading state, an interactive drill-down treemap, and a breadcrumb bar
///   to navigate back up), built on `UIDesignSystem`'s Liquid Glass
///   token/component vocabulary.
public enum SpaceLensModule {
    /// Semantic version of this module's public API surface.
    public static let apiVersion = "1.0.0"
}
