import Foundation

/// Static CSS knowledge for the native service: property docs + keyword values, at-rules, pseudo classes / elements, functions, colors.
/// Stored as compact strings and parsed on first use (a few tens of KB, built once; dropped never because it is tiny).
enum NWCssData {
    struct Prop { var name: String; var doc: String; var values: [String] }

    // name | description | space separated keyword values
    private static let propTable = """
    display|Sets the inner and outer display type of an element.|block inline inline-block flex inline-flex grid inline-grid flow-root none contents table table-row table-cell list-item
    position|How an element is positioned in the document.|static relative absolute fixed sticky
    top|Vertical offset of a positioned element from the top edge of its containing block.|auto
    right|Horizontal offset of a positioned element from the right edge of its containing block.|auto
    bottom|Vertical offset of a positioned element from the bottom edge of its containing block.|auto
    left|Horizontal offset of a positioned element from the left edge of its containing block.|auto
    inset|Shorthand for top, right, bottom and left.|auto
    z-index|Stack order of a positioned element and its descendants.|auto
    float|Places an element on the left or right of its container, letting text wrap around it.|left right none inline-start inline-end
    clear|Whether an element must be moved below preceding floats.|none left right both inline-start inline-end
    width|Width of an element's content box.|auto min-content max-content fit-content stretch
    height|Height of an element's content box.|auto min-content max-content fit-content stretch
    min-width|Minimum width of an element.|auto min-content max-content fit-content stretch
    max-width|Maximum width of an element.|none min-content max-content fit-content stretch
    min-height|Minimum height of an element.|auto min-content max-content fit-content stretch
    max-height|Maximum height of an element.|none min-content max-content fit-content stretch
    aspect-ratio|Preferred aspect ratio of the box.|auto
    box-sizing|How the total width and height of an element is calculated.|content-box border-box
    margin|Margin area on all four sides of an element.|auto
    margin-top|Margin area on the top of an element.|auto
    margin-right|Margin area on the right of an element.|auto
    margin-bottom|Margin area on the bottom of an element.|auto
    margin-left|Margin area on the left of an element.|auto
    margin-inline|Margin on the inline start and end sides.|auto
    margin-block|Margin on the block start and end sides.|auto
    padding|Padding area on all four sides of an element.|
    padding-top|Padding area on the top of an element.|
    padding-right|Padding area on the right of an element.|
    padding-bottom|Padding area on the bottom of an element.|
    padding-left|Padding area on the left of an element.|
    padding-inline|Padding on the inline start and end sides.|
    padding-block|Padding on the block start and end sides.|
    overflow|What happens when content overflows the box.|visible hidden clip scroll auto
    overflow-x|What happens when content overflows horizontally.|visible hidden clip scroll auto
    overflow-y|What happens when content overflows vertically.|visible hidden clip scroll auto
    overscroll-behavior|What happens when the scroll boundary is reached.|auto contain none
    visibility|Shows or hides an element without changing the layout.|visible hidden collapse
    opacity|Transparency of an element (0 to 1).|
    flex|Shorthand for flex-grow, flex-shrink and flex-basis.|auto initial none
    flex-grow|How much a flex item grows relative to the others.|
    flex-shrink|How much a flex item shrinks relative to the others.|
    flex-basis|Initial main size of a flex item.|auto content min-content max-content fit-content
    flex-direction|Main axis direction of a flex container.|row row-reverse column column-reverse
    flex-wrap|Whether flex items wrap onto multiple lines.|nowrap wrap wrap-reverse
    flex-flow|Shorthand for flex-direction and flex-wrap.|row row-reverse column column-reverse nowrap wrap wrap-reverse
    order|Order of a flex or grid item.|
    justify-content|Alignment of items along the main axis.|flex-start flex-end center space-between space-around space-evenly start end stretch normal left right
    justify-items|Default justify-self for all items of a grid container.|start end center stretch baseline normal legacy
    justify-self|Alignment of an item along the inline axis.|auto start end center stretch baseline normal flex-start flex-end self-start self-end
    align-items|Alignment of items along the cross axis.|flex-start flex-end center baseline stretch start end normal self-start self-end
    align-content|Distribution of space between lines on the cross axis.|flex-start flex-end center space-between space-around space-evenly stretch start end normal baseline
    align-self|Overrides align-items for a single item.|auto flex-start flex-end center baseline stretch start end normal self-start self-end
    place-content|Shorthand for align-content and justify-content.|center start end space-between space-around space-evenly stretch
    place-items|Shorthand for align-items and justify-items.|center start end stretch baseline
    place-self|Shorthand for align-self and justify-self.|auto center start end stretch
    gap|Gaps between rows and columns.|normal
    row-gap|Gap between rows.|normal
    column-gap|Gap between columns.|normal
    grid|Shorthand for the grid template and auto-placement properties.|none
    grid-template|Shorthand for grid-template-rows, columns and areas.|none
    grid-template-columns|Column tracks of the grid.|none subgrid auto min-content max-content repeat() minmax() fit-content()
    grid-template-rows|Row tracks of the grid.|none subgrid auto min-content max-content repeat() minmax() fit-content()
    grid-template-areas|Named grid areas.|none
    grid-area|Grid item placement shorthand.|auto
    grid-column|Grid item column placement shorthand.|auto span
    grid-row|Grid item row placement shorthand.|auto span
    grid-column-start|Start line of a grid item's column.|auto span
    grid-column-end|End line of a grid item's column.|auto span
    grid-row-start|Start line of a grid item's row.|auto span
    grid-row-end|End line of a grid item's row.|auto span
    grid-auto-flow|How auto-placed items are flowed into the grid.|row column dense row dense column dense
    grid-auto-columns|Size of implicitly created columns.|auto min-content max-content minmax()
    grid-auto-rows|Size of implicitly created rows.|auto min-content max-content minmax()
    color|Foreground color of text and text decorations.|currentColor transparent inherit
    background|Shorthand for all background properties.|none transparent
    background-color|Background color of an element.|transparent currentColor
    background-image|One or more background images.|none url() linear-gradient() radial-gradient() conic-gradient()
    background-position|Initial position of each background image.|top bottom left right center
    background-size|Size of the background images.|auto cover contain
    background-repeat|How background images repeat.|repeat repeat-x repeat-y no-repeat space round
    background-attachment|Whether the background scrolls with the viewport or its element.|scroll fixed local
    background-clip|Extent of the background painting area.|border-box padding-box content-box text
    background-origin|Background positioning area.|border-box padding-box content-box
    background-blend-mode|How background layers blend.|normal multiply screen overlay darken lighten color-dodge color-burn hard-light soft-light difference exclusion hue saturation color luminosity
    border|Shorthand for border-width, border-style and border-color.|none hidden solid dashed dotted double groove ridge inset outset thin medium thick
    border-top|Shorthand for the top border.|none solid dashed dotted
    border-right|Shorthand for the right border.|none solid dashed dotted
    border-bottom|Shorthand for the bottom border.|none solid dashed dotted
    border-left|Shorthand for the left border.|none solid dashed dotted
    border-width|Width of the border on all sides.|thin medium thick
    border-style|Line style of the border on all sides.|none hidden solid dashed dotted double groove ridge inset outset
    border-color|Color of the border on all sides.|currentColor transparent
    border-radius|Rounds the corners of the border box.|
    border-top-left-radius|Rounds the top-left corner.|
    border-top-right-radius|Rounds the top-right corner.|
    border-bottom-left-radius|Rounds the bottom-left corner.|
    border-bottom-right-radius|Rounds the bottom-right corner.|
    border-collapse|Whether table borders are collapsed into a single border.|collapse separate
    border-spacing|Distance between the borders of adjacent table cells.|
    outline|Shorthand for outline-width, outline-style and outline-color.|none auto solid dashed dotted thin medium thick
    outline-offset|Space between the outline and the border edge.|
    outline-color|Color of the outline.|currentColor invert
    outline-style|Line style of the outline.|auto none solid dashed dotted double groove ridge inset outset
    outline-width|Width of the outline.|thin medium thick
    box-shadow|Shadow effects around an element's frame.|none inset
    text-shadow|Shadows applied to text.|none
    font|Shorthand for font-style, weight, size, line-height and family.|caption icon menu message-box small-caption status-bar
    font-family|Font family list.|serif sans-serif monospace cursive fantasy system-ui ui-sans-serif ui-serif ui-monospace ui-rounded inherit
    font-size|Size of the font.|xx-small x-small small medium large x-large xx-large xxx-large smaller larger
    font-weight|Weight (boldness) of the font.|normal bold bolder lighter 100 200 300 400 500 600 700 800 900
    font-style|Font style: normal, italic or oblique.|normal italic oblique
    font-variant|Small-caps and other font variants.|normal small-caps
    font-stretch|Normal, condensed or expanded face.|normal condensed expanded
    font-display|How a font face is displayed while loading.|auto block swap fallback optional
    line-height|Height of a line box.|normal
    letter-spacing|Spacing between characters.|normal
    word-spacing|Spacing between words.|normal
    text-align|Horizontal alignment of inline content.|left right center justify start end match-parent
    text-align-last|Alignment of the last line of a block.|auto start end left right center justify
    text-decoration|Shorthand for text-decoration-line, color, style and thickness.|none underline overline line-through dotted dashed solid double wavy
    text-decoration-line|Kind of decoration line.|none underline overline line-through
    text-decoration-color|Color of the decoration line.|currentColor
    text-decoration-style|Style of the decoration line.|solid double dotted dashed wavy
    text-decoration-thickness|Thickness of the decoration line.|auto from-font
    text-underline-offset|Offset of an underline from its original position.|auto
    text-transform|Capitalization of text.|none capitalize uppercase lowercase full-width
    text-indent|Indentation of the first line of a block.|
    text-overflow|How overflowed content is signaled.|clip ellipsis
    text-wrap|How text wraps within an element.|wrap nowrap balance pretty stable
    white-space|How white space is handled.|normal nowrap pre pre-wrap pre-line break-spaces
    word-break|Where line breaks may occur within words.|normal break-all keep-all break-word
    overflow-wrap|Whether the browser may break within an otherwise unbreakable word.|normal break-word anywhere
    word-wrap|Legacy name of overflow-wrap.|normal break-word
    hyphens|How words are hyphenated.|none manual auto
    vertical-align|Vertical alignment of an inline or table-cell box.|baseline sub super text-top text-bottom middle top bottom
    direction|Text direction.|ltr rtl
    writing-mode|Whether lines are laid out horizontally or vertically.|horizontal-tb vertical-rl vertical-lr
    tab-size|Size of a tab character.|
    list-style|Shorthand for list-style-type, position and image.|none disc circle square decimal inside outside
    list-style-type|Marker type of list items.|none disc circle square decimal decimal-leading-zero lower-roman upper-roman lower-alpha upper-alpha lower-latin upper-latin
    list-style-position|Marker position relative to the principal box.|inside outside
    list-style-image|Image used as the list item marker.|none url()
    content|Replaces an element's content with generated content (::before / ::after).|none normal "" attr() counter() open-quote close-quote
    quotes|Quotation marks for q and generated content.|none auto
    counter-reset|Resets CSS counters.|none
    counter-increment|Increments CSS counters.|none
    cursor|Mouse cursor shown over an element.|auto default none context-menu help pointer progress wait cell crosshair text vertical-text alias copy move no-drop not-allowed grab grabbing all-scroll col-resize row-resize n-resize e-resize s-resize w-resize ew-resize ns-resize nesw-resize nwse-resize zoom-in zoom-out
    pointer-events|Whether an element can be the target of pointer events.|auto none all visiblePainted visibleFill visibleStroke visible painted fill stroke
    user-select|Whether the user can select text.|auto none text all contain
    resize|Whether an element is resizable by the user.|none both horizontal vertical block inline
    appearance|Native appearance of UI controls.|none auto menulist-button textfield
    accent-color|Accent color for user interface controls.|auto
    caret-color|Color of the text insertion caret.|auto currentColor
    scroll-behavior|Smooth or instant scrolling.|auto smooth
    scroll-snap-type|How strictly snap points are enforced.|none x y block inline both mandatory proximity
    scroll-snap-align|Snap position of an element.|none start end center
    scroll-margin|Scroll snap margin of an element.|
    scroll-padding|Scroll snap padding of a scroll container.|
    scrollbar-width|Width of the scrollbar.|auto thin none
    scrollbar-color|Colors of the scrollbar track and thumb.|auto
    scrollbar-gutter|Space reserved for the scrollbar.|auto stable
    touch-action|How a touch screen may manipulate an element.|auto none pan-x pan-y pinch-zoom manipulation
    transform|Rotates, scales, skews or translates an element.|none translate() translateX() translateY() scale() rotate() skew() matrix() perspective()
    transform-origin|Origin for an element's transformations.|top bottom left right center
    transform-style|Whether children are positioned in 3D space.|flat preserve-3d
    translate|Individual translate transform.|none
    rotate|Individual rotate transform.|none
    scale|Individual scale transform.|none
    perspective|Distance between the z=0 plane and the user.|none
    backface-visibility|Whether the back face of an element is visible.|visible hidden
    transition|Shorthand for the transition properties.|none all ease ease-in ease-out ease-in-out linear
    transition-property|Properties that transition.|none all
    transition-duration|Duration of transitions.|
    transition-timing-function|Timing function of transitions.|ease ease-in ease-out ease-in-out linear step-start step-end cubic-bezier() steps()
    transition-delay|Delay before transitions start.|
    transition-behavior|Whether transitions start for discrete properties.|normal allow-discrete
    animation|Shorthand for the animation properties.|none infinite alternate forwards backwards both paused running ease linear
    animation-name|Names of the @keyframes to apply.|none
    animation-duration|Duration of one animation cycle.|
    animation-timing-function|Timing function of the animation.|ease ease-in ease-out ease-in-out linear step-start step-end cubic-bezier() steps()
    animation-delay|Delay before the animation starts.|
    animation-iteration-count|Number of times the animation repeats.|infinite
    animation-direction|Whether the animation plays forwards, backwards or alternates.|normal reverse alternate alternate-reverse
    animation-fill-mode|What values apply before and after the animation.|none forwards backwards both
    animation-play-state|Whether the animation is running or paused.|running paused
    filter|Graphical effects (blur, brightness...) on an element.|none blur() brightness() contrast() drop-shadow() grayscale() hue-rotate() invert() opacity() saturate() sepia() url()
    backdrop-filter|Graphical effects behind an element.|none blur() brightness() contrast() grayscale() saturate()
    mix-blend-mode|How an element blends with its backdrop.|normal multiply screen overlay darken lighten color-dodge color-burn hard-light soft-light difference exclusion hue saturation color luminosity
    isolation|Whether an element creates a new stacking context.|auto isolate
    clip-path|Clips an element to a basic shape or SVG path.|none circle() ellipse() inset() polygon() path() url()
    mask|Shorthand for the mask properties.|none
    object-fit|How replaced content fits its box.|fill contain cover none scale-down
    object-position|Alignment of replaced content within its box.|top bottom left right center
    image-rendering|How images are scaled.|auto crisp-edges pixelated smooth
    will-change|Hints at properties that will change.|auto scroll-position contents transform opacity
    contain|Containment of an element's subtree.|none strict content size layout style paint inline-size
    content-visibility|Whether an element renders its contents.|visible auto hidden
    container-type|Makes an element a query container.|normal size inline-size
    container-name|Name of the query container.|none
    container|Shorthand for container-name and container-type.|
    table-layout|Algorithm used to lay out table cells.|auto fixed
    caption-side|Side of a table on which the caption is placed.|top bottom
    empty-cells|Whether borders and backgrounds show for empty cells.|show hide
    columns|Shorthand for column-width and column-count.|auto
    column-count|Number of columns.|auto
    column-width|Ideal column width.|auto
    column-rule|Rule between columns.|
    break-inside|How a page, column or region break behaves inside a box.|auto avoid avoid-page avoid-column
    orphans|Minimum number of lines at the bottom of a fragment.|
    widows|Minimum number of lines at the top of a fragment.|
    fill|Color used to paint SVG shapes.|none currentColor
    stroke|Color used to paint SVG outlines.|none currentColor
    stroke-width|Width of the SVG stroke.|
    stroke-linecap|Shape of stroke line ends.|butt round square
    stroke-linejoin|Shape of stroke corners.|miter round bevel
    stroke-dasharray|Pattern of dashes and gaps of the stroke.|none
    stroke-dashoffset|Offset of the dash pattern.|
    fill-opacity|Opacity of the SVG fill.|
    stroke-opacity|Opacity of the SVG stroke.|
    color-scheme|Color schemes an element supports.|normal light dark light dark
    forced-color-adjust|Whether forced colors mode applies.|auto none
    all|Resets all properties except unicode-bidi and direction.|initial inherit unset revert revert-layer
    inline-size|Size of an element in the inline direction.|auto min-content max-content fit-content
    block-size|Size of an element in the block direction.|auto min-content max-content fit-content
    margin-inline-start|Margin at the inline start.|auto
    margin-inline-end|Margin at the inline end.|auto
    padding-inline-start|Padding at the inline start.|
    padding-inline-end|Padding at the inline end.|
    inset-inline|Inset on the inline start and end sides.|auto
    inset-block|Inset on the block start and end sides.|auto
    text-rendering|Hint about how to optimize text rendering.|auto optimizeSpeed optimizeLegibility geometricPrecision
    font-smoothing|Font smoothing (non-standard).|auto antialiased subpixel-antialiased
    -webkit-font-smoothing|Font smoothing on WebKit.|auto antialiased subpixel-antialiased
    -moz-osx-font-smoothing|Font smoothing on Firefox for macOS.|auto grayscale
    -webkit-line-clamp|Limits text to a number of lines (with -webkit-box).|none
    -webkit-appearance|Native appearance of UI controls (WebKit).|none auto
    -webkit-text-fill-color|Fill color of text (WebKit).|currentColor transparent
    -webkit-tap-highlight-color|Highlight color on tap (WebKit).|transparent
    -webkit-background-clip|Background clip (WebKit).|text border-box padding-box content-box
    """

    static let props: [String: Prop] = {
        var d: [String: Prop] = [:]
        for line in propTable.split(separator: "\n") {
            let p = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard p.count == 3, !p[0].isEmpty else { continue }
            d[p[0]] = Prop(name: p[0], doc: p[1], values: p[2].split(separator: " ").map(String.init))
        }
        // Names without docs from the older completion table.
        for name in CompletionData.cssProperties where d[name] == nil { d[name] = Prop(name: name, doc: "", values: CompletionData.cssValues[name].map { CompletionData.words($0) } ?? []) }
        return d
    }()

    static let sortedPropNames: [String] = props.keys.sorted()

    static func isProperty(_ name: String) -> Bool { props[name] != nil || name.hasPrefix("--") || name.hasPrefix("-webkit-") || name.hasPrefix("-moz-") || name.hasPrefix("-ms-") }

    static let globalValues = ["inherit", "initial", "unset", "revert", "revert-layer"]

    // color-valued properties (get named colors and color functions)
    static let colorProps: Set<String> = ["color", "background", "background-color", "border", "border-color", "border-top", "border-right", "border-bottom", "border-left",
                                          "border-top-color", "border-right-color", "border-bottom-color", "border-left-color", "outline", "outline-color", "fill", "stroke",
                                          "caret-color", "accent-color", "text-decoration", "text-decoration-color", "box-shadow", "text-shadow", "column-rule-color",
                                          "scrollbar-color", "-webkit-text-fill-color", "-webkit-tap-highlight-color", "mask", "flood-color", "stop-color", "lighting-color"]

    // MARK: at-rules

    static let atRules: [(name: String, doc: String, snippet: String)] = [
        ("media", "Applies styles when a media query matches.", "media ${1:(min-width: 768px)} {\n\t$0\n}"),
        ("import", "Imports another stylesheet.", "import url(\"$0\");"),
        ("font-face", "Defines a custom font to download.", "font-face {\n\tfont-family: $1;\n\tsrc: url(\"$2\");\n\t$0\n}"),
        ("keyframes", "Defines the steps of a CSS animation.", "keyframes ${1:name} {\n\tfrom { $2 }\n\tto { $0 }\n}"),
        ("supports", "Applies styles when the browser supports a feature.", "supports (${1:display: grid}) {\n\t$0\n}"),
        ("layer", "Declares a cascade layer.", "layer ${1:name};"),
        ("container", "Applies styles based on the size of a query container.", "container ${1:(min-width: 400px)} {\n\t$0\n}"),
        ("charset", "Specifies the character encoding of the stylesheet.", "charset \"UTF-8\";"),
        ("namespace", "Declares an XML namespace.", "namespace $0;"),
        ("page", "Applies styles when printing a page.", "page {\n\t$0\n}"),
        ("property", "Registers a custom property with type and default.", "property --${1:name} {\n\tsyntax: '<${2:length}>';\n\tinherits: ${3:false};\n\tinitial-value: ${4:0};\n}"),
        ("scope", "Scopes styles to a DOM subtree.", "scope (${1:.card}) {\n\t$0\n}"),
        ("starting-style", "Starting values for transitions on first render.", "starting-style {\n\t$0\n}"),
        ("counter-style", "Defines a custom counter style.", "counter-style ${1:name} {\n\t$0\n}"),
        ("font-feature-values", "Names OpenType feature values.", "font-feature-values ${1:Font} {\n\t$0\n}"),
        ("view-transition", "Opts a page into cross-document view transitions.", "view-transition {\n\tnavigation: auto;\n}"),
    ]

    // Tailwind / PostCSS / Sass / Less additions are offered by the Tailwind service and by file language.
    static let sassAtRules: [(String, String)] = [("mixin", "Defines a mixin."), ("include", "Includes a mixin."), ("use", "Loads a module."), ("forward", "Re-exports a module."),
                                                  ("extend", "Extends another selector."), ("function", "Defines a function."), ("return", "Returns a value from a function."),
                                                  ("if", "Conditional."), ("else", "Else branch."), ("each", "Loops over a list or map."), ("for", "Loops over a range."),
                                                  ("while", "Loops while a condition holds."), ("debug", "Prints a debug message."), ("warn", "Prints a warning."),
                                                  ("error", "Throws an error."), ("at-root", "Emits rules at the document root."), ("content", "Placeholder for a mixin block.")]

    // MARK: pseudo classes / elements

    static let pseudoClasses: [(name: String, doc: String)] = [
        ("hover", "Matches when a pointer hovers over the element."), ("focus", "Matches when the element has focus."),
        ("focus-visible", "Matches when the element has focus and the browser shows a focus indicator."),
        ("focus-within", "Matches an element that has focus or contains an element with focus."),
        ("active", "Matches while the element is being activated (for example clicked)."), ("visited", "Matches visited links."),
        ("link", "Matches unvisited links."), ("any-link", "Matches any link."), ("target", "Matches the element whose id matches the URL fragment."),
        ("first-child", "Matches the first child of its parent."), ("last-child", "Matches the last child of its parent."),
        ("only-child", "Matches an element that is the only child."), ("first-of-type", "Matches the first sibling of its type."),
        ("last-of-type", "Matches the last sibling of its type."), ("only-of-type", "Matches an element with no siblings of its type."),
        ("nth-child()", "Matches elements by position among siblings (an+b)."), ("nth-last-child()", "Matches by position counting from the end."),
        ("nth-of-type()", "Matches by position among siblings of the same type."), ("nth-last-of-type()", "Matches by position among same-type siblings from the end."),
        ("not()", "Matches elements that do not match the selector list."), ("is()", "Matches any selector in the list (forgiving)."),
        ("where()", "Like :is() but with zero specificity."), ("has()", "Matches an element if any relative selector matches."),
        ("root", "Matches the document root element."), ("empty", "Matches an element with no children."),
        ("checked", "Matches checked inputs, options and radios."), ("disabled", "Matches disabled form controls."), ("enabled", "Matches enabled form controls."),
        ("required", "Matches required form controls."), ("optional", "Matches optional form controls."), ("valid", "Matches valid form controls."),
        ("invalid", "Matches invalid form controls."), ("read-only", "Matches elements not editable by the user."), ("read-write", "Matches editable elements."),
        ("placeholder-shown", "Matches an input currently showing its placeholder."), ("indeterminate", "Matches indeterminate checkboxes and progress bars."),
        ("default", "Matches the default form control."), ("in-range", "Matches inputs whose value is in range."), ("out-of-range", "Matches inputs whose value is out of range."),
        ("autofill", "Matches an input autofilled by the browser."), ("lang()", "Matches by language."), ("dir()", "Matches by text direction."),
        ("fullscreen", "Matches an element in fullscreen mode."), ("modal", "Matches a modal dialog or fullscreen element."), ("popover-open", "Matches an open popover."),
        ("host", "Matches the shadow host."), ("host()", "Matches the shadow host when it matches the selector."), ("defined", "Matches defined elements."),
        ("state()", "Matches custom element states."), ("target-within", "Matches an element that is or contains the target."),
        ("user-invalid", "Matches invalid controls after user interaction."), ("user-valid", "Matches valid controls after user interaction."),
    ]
    static let pseudoElements: [(name: String, doc: String)] = [
        ("before", "Generated content before the element's content."), ("after", "Generated content after the element's content."),
        ("first-line", "The first formatted line of a block."), ("first-letter", "The first letter of the first line of a block."),
        ("selection", "The part of the document selected by the user."), ("placeholder", "The placeholder text of an input."),
        ("marker", "The marker box of a list item."), ("backdrop", "The backdrop of a fullscreen or modal element."),
        ("file-selector-button", "The button of a file input."), ("cue", "WebVTT cues."), ("part()", "A shadow part."), ("slotted()", "Elements assigned to a slot."),
        ("target-text", "Text targeted by a text fragment."), ("view-transition", "Root of the view transition overlay."),
        ("-webkit-scrollbar", "The scrollbar (WebKit)."), ("-webkit-scrollbar-thumb", "The scrollbar thumb (WebKit)."), ("-webkit-scrollbar-track", "The scrollbar track (WebKit)."),
        ("-webkit-search-cancel-button", "Search input clear button (WebKit)."), ("-webkit-inner-spin-button", "Number input spin buttons (WebKit)."),
    ]

    // MARK: functions, units, colors

    static let valueFunctions: [(String, String)] = [
        ("var()", "var(--name, fallback)"), ("calc()", "calc(a + b)"), ("min()", "min(a, b)"), ("max()", "max(a, b)"), ("clamp()", "clamp(min, preferred, max)"),
        ("rgb()", "rgb(r g b / a)"), ("rgba()", "rgba(r, g, b, a)"), ("hsl()", "hsl(h s l / a)"), ("hsla()", "hsla(h, s, l, a)"), ("hwb()", "hwb(h w b)"),
        ("oklch()", "oklch(l c h)"), ("oklab()", "oklab(l a b)"), ("lab()", "lab(l a b)"), ("lch()", "lch(l c h)"), ("color-mix()", "color-mix(in srgb, a, b)"),
        ("color()", "color(srgb r g b)"), ("light-dark()", "light-dark(light, dark)"), ("url()", "url(path)"), ("linear-gradient()", "linear-gradient(angle, stops)"),
        ("radial-gradient()", "radial-gradient(shape, stops)"), ("conic-gradient()", "conic-gradient(from angle, stops)"), ("repeating-linear-gradient()", "repeating-linear-gradient"),
        ("env()", "env(safe-area-inset-top)"), ("attr()", "attr(name)"), ("counter()", "counter(name)"), ("minmax()", "minmax(min, max)"), ("repeat()", "repeat(n, track)"),
        ("fit-content()", "fit-content(limit)"), ("translate()", "translate(x, y)"), ("scale()", "scale(x, y)"), ("rotate()", "rotate(angle)"), ("blur()", "blur(radius)"),
        ("cubic-bezier()", "cubic-bezier(a, b, c, d)"), ("steps()", "steps(n, jump)"),
    ]

    static let units = ["px", "rem", "em", "%", "vh", "vw", "vmin", "vmax", "dvh", "svh", "lvh", "dvw", "ch", "ex", "cm", "mm", "in", "pt", "pc", "fr", "deg", "rad", "turn", "s", "ms", "cqw", "cqh"]

    static let namedColors: [String: String] = {
        var d: [String: String] = [:]
        let table = """
        aliceblue f0f8ff antiquewhite faebd7 aqua 00ffff aquamarine 7fffd4 azure f0ffff beige f5f5dc bisque ffe4c4 black 000000 blanchedalmond ffebcd blue 0000ff blueviolet 8a2be2 \
        brown a52a2a burlywood deb887 cadetblue 5f9ea0 chartreuse 7fff00 chocolate d2691e coral ff7f50 cornflowerblue 6495ed cornsilk fff8dc crimson dc143c cyan 00ffff \
        darkblue 00008b darkcyan 008b8b darkgoldenrod b8860b darkgray a9a9a9 darkgreen 006400 darkgrey a9a9a9 darkkhaki bdb76b darkmagenta 8b008b darkolivegreen 556b2f \
        darkorange ff8c00 darkorchid 9932cc darkred 8b0000 darksalmon e9967a darkseagreen 8fbc8f darkslateblue 483d8b darkslategray 2f4f4f darkslategrey 2f4f4f \
        darkturquoise 00ced1 darkviolet 9400d3 deeppink ff1493 deepskyblue 00bfff dimgray 696969 dimgrey 696969 dodgerblue 1e90ff firebrick b22222 floralwhite fffaf0 \
        forestgreen 228b22 fuchsia ff00ff gainsboro dcdcdc ghostwhite f8f8ff gold ffd700 goldenrod daa520 gray 808080 green 008000 greenyellow adff2f grey 808080 \
        honeydew f0fff0 hotpink ff69b4 indianred cd5c5c indigo 4b0082 ivory fffff0 khaki f0e68c lavender e6e6fa lavenderblush fff0f5 lawngreen 7cfc00 lemonchiffon fffacd \
        lightblue add8e6 lightcoral f08080 lightcyan e0ffff lightgoldenrodyellow fafad2 lightgray d3d3d3 lightgreen 90ee90 lightgrey d3d3d3 lightpink ffb6c1 \
        lightsalmon ffa07a lightseagreen 20b2aa lightskyblue 87cefa lightslategray 778899 lightslategrey 778899 lightsteelblue b0c4de lightyellow ffffe0 lime 00ff00 \
        limegreen 32cd32 linen faf0e6 magenta ff00ff maroon 800000 mediumaquamarine 66cdaa mediumblue 0000cd mediumorchid ba55d3 mediumpurple 9370db mediumseagreen 3cb371 \
        mediumslateblue 7b68ee mediumspringgreen 00fa9a mediumturquoise 48d1cc mediumvioletred c71585 midnightblue 191970 mintcream f5fffa mistyrose ffe4e1 moccasin ffe4b5 \
        navajowhite ffdead navy 000080 oldlace fdf5e6 olive 808000 olivedrab 6b8e23 orange ffa500 orangered ff4500 orchid da70d6 palegoldenrod eee8aa palegreen 98fb98 \
        paleturquoise afeeee palevioletred db7093 papayawhip ffefd5 peachpuff ffdab9 peru cd853f pink ffc0cb plum dda0dd powderblue b0e0e6 purple 800080 rebeccapurple 663399 \
        red ff0000 rosybrown bc8f8f royalblue 4169e1 saddlebrown 8b4513 salmon fa8072 sandybrown f4a460 seagreen 2e8b57 seashell fff5ee sienna a0522d silver c0c0c0 \
        skyblue 87ceeb slateblue 6a5acd slategray 708090 slategrey 708090 snow fffafa springgreen 00ff7f steelblue 4682b4 tan d2b48c teal 008080 thistle d8bfd8 tomato ff6347 \
        turquoise 40e0d0 violet ee82ee wheat f5deb3 white ffffff whitesmoke f5f5f5 yellow ffff00 yellowgreen 9acd32
        """
        let t = table.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\\" }).map(String.init).filter { !$0.isEmpty }
        var i = 0
        while i + 1 < t.count { d[t[i]] = "#" + t[i + 1]; i += 2 }
        return d
    }()

    static let mediaFeatures = ["width", "min-width", "max-width", "height", "min-height", "max-height", "aspect-ratio", "orientation", "resolution", "prefers-color-scheme",
                                "prefers-reduced-motion", "prefers-contrast", "hover", "pointer", "any-hover", "display-mode", "min-resolution", "max-resolution", "forced-colors", "color", "scripting"]

    static let tagNames: Set<String> = Set(NWHtmlData.tags.map(\.name))

    /// Parses `#rgb`, `#rrggbb`, `#rrggbbaa` into 0...255 components + alpha 0...1.
    static func parseHex(_ s: String) -> (r: Int, g: Int, b: Int, a: Double)? {
        var h = s
        if h.hasPrefix("#") { h.removeFirst() }
        let digits = Array(h.utf8)
        guard digits.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) || ($0 >= 65 && $0 <= 70) }) else { return nil }
        func hex(_ a: Int, _ n: Int) -> Int { Int(String(h[h.index(h.startIndex, offsetBy: a)..<h.index(h.startIndex, offsetBy: a + n)]), radix: 16) ?? 0 }
        switch h.count {
        case 3: return (hex(0, 1) * 17, hex(1, 1) * 17, hex(2, 1) * 17, 1)
        case 4: return (hex(0, 1) * 17, hex(1, 1) * 17, hex(2, 1) * 17, Double(hex(3, 1) * 17) / 255)
        case 6: return (hex(0, 2), hex(2, 2), hex(4, 2), 1)
        case 8: return (hex(0, 2), hex(2, 2), hex(4, 2), Double(hex(6, 2)) / 255)
        default: return nil
        }
    }
}
