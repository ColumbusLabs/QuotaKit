func menuCardHighlightShouldRender(
    highlighted: Bool,
    enabled: Bool,
    allowsHighlight: Bool,
    hoverHighlightEnabled: Bool,
    keyboardSelected: Bool) -> Bool
{
    highlighted && enabled && allowsHighlight && (hoverHighlightEnabled || keyboardSelected)
}
