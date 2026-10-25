import Foundation

/// Utilities whose CSS does not depend on the theme: `name -> declarations`. Parsed lazily on the first Tailwind request.
/// Format: `G prefix|property|key=value key=value` expands to `prefix-key { property: value }` (key `_` = the bare prefix),
/// `S name|prop: value; prop: value` is one utility. `~` inside a value stands for a space.
enum NWTailwindStatic {
    private static let table = """
    S container|width: 100%
    S sr-only|position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border-width: 0
    S not-sr-only|position: static; width: auto; height: auto; padding: 0; margin: 0; overflow: visible; clip: auto; white-space: normal
    S truncate|overflow: hidden; text-overflow: ellipsis; white-space: nowrap
    S line-clamp-none|overflow: visible; display: block; -webkit-box-orient: horizontal; -webkit-line-clamp: none
    S antialiased|-webkit-font-smoothing: antialiased; -moz-osx-font-smoothing: grayscale
    S subpixel-antialiased|-webkit-font-smoothing: auto; -moz-osx-font-smoothing: auto
    S underline|text-decoration-line: underline
    S overline|text-decoration-line: overline
    S line-through|text-decoration-line: line-through
    S no-underline|text-decoration-line: none
    S italic|font-style: italic
    S not-italic|font-style: normal
    S uppercase|text-transform: uppercase
    S lowercase|text-transform: lowercase
    S capitalize|text-transform: capitalize
    S normal-case|text-transform: none
    S ordinal|font-variant-numeric: ordinal
    S slashed-zero|font-variant-numeric: slashed-zero
    S lining-nums|font-variant-numeric: lining-nums
    S oldstyle-nums|font-variant-numeric: oldstyle-nums
    S proportional-nums|font-variant-numeric: proportional-nums
    S tabular-nums|font-variant-numeric: tabular-nums
    S diagonal-fractions|font-variant-numeric: diagonal-fractions
    S stacked-fractions|font-variant-numeric: stacked-fractions
    S normal-nums|font-variant-numeric: normal
    S visible|visibility: visible
    S invisible|visibility: hidden
    S collapse|visibility: collapse
    S hidden|display: none
    S isolate|isolation: isolate
    S isolation-auto|isolation: auto
    S transform-gpu|transform: translate3d(var(--tw-translate-x), var(--tw-translate-y), 0) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y))
    S transform|transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y))
    S transform-none|transform: none
    S grow|flex-grow: 1
    S shrink|flex-shrink: 1
    S outline-none|outline: 2px solid transparent; outline-offset: 2px
    S outline-hidden|outline: 2px solid transparent; outline-offset: 2px
    S outline|outline-style: solid
    S outline-dashed|outline-style: dashed
    S outline-dotted|outline-style: dotted
    S outline-double|outline-style: double
    S ring-inset|--tw-ring-inset: inset
    S resize|resize: both
    S filter|filter: var(--tw-blur) var(--tw-brightness) var(--tw-contrast) var(--tw-grayscale) var(--tw-hue-rotate) var(--tw-invert) var(--tw-saturate) var(--tw-sepia) var(--tw-drop-shadow)
    S filter-none|filter: none
    S backdrop-filter|backdrop-filter: var(--tw-backdrop-blur) var(--tw-backdrop-brightness) var(--tw-backdrop-contrast) var(--tw-backdrop-grayscale) var(--tw-backdrop-hue-rotate) var(--tw-backdrop-invert) var(--tw-backdrop-opacity) var(--tw-backdrop-saturate) var(--tw-backdrop-sepia)
    S backdrop-filter-none|backdrop-filter: none
    S transition|transition-property: color, background-color, border-color, text-decoration-color, fill, stroke, opacity, box-shadow, transform, filter, backdrop-filter; transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1); transition-duration: 150ms
    S transition-all|transition-property: all; transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1); transition-duration: 150ms
    S transition-colors|transition-property: color, background-color, border-color, text-decoration-color, fill, stroke; transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1); transition-duration: 150ms
    S transition-opacity|transition-property: opacity; transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1); transition-duration: 150ms
    S transition-shadow|transition-property: box-shadow; transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1); transition-duration: 150ms
    S transition-transform|transition-property: transform; transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1); transition-duration: 150ms
    S transition-none|transition-property: none
    S bg-none|background-image: none
    S bg-gradient-to-t|background-image: linear-gradient(to top, var(--tw-gradient-stops))
    S bg-gradient-to-tr|background-image: linear-gradient(to top right, var(--tw-gradient-stops))
    S bg-gradient-to-r|background-image: linear-gradient(to right, var(--tw-gradient-stops))
    S bg-gradient-to-br|background-image: linear-gradient(to bottom right, var(--tw-gradient-stops))
    S bg-gradient-to-b|background-image: linear-gradient(to bottom, var(--tw-gradient-stops))
    S bg-gradient-to-bl|background-image: linear-gradient(to bottom left, var(--tw-gradient-stops))
    S bg-gradient-to-l|background-image: linear-gradient(to left, var(--tw-gradient-stops))
    S bg-gradient-to-tl|background-image: linear-gradient(to top left, var(--tw-gradient-stops))
    S bg-linear-to-t|background-image: linear-gradient(to top in oklab, var(--tw-gradient-stops))
    S bg-linear-to-tr|background-image: linear-gradient(to top right in oklab, var(--tw-gradient-stops))
    S bg-linear-to-r|background-image: linear-gradient(to right in oklab, var(--tw-gradient-stops))
    S bg-linear-to-br|background-image: linear-gradient(to bottom right in oklab, var(--tw-gradient-stops))
    S bg-linear-to-b|background-image: linear-gradient(to bottom in oklab, var(--tw-gradient-stops))
    S bg-linear-to-bl|background-image: linear-gradient(to bottom left in oklab, var(--tw-gradient-stops))
    S bg-linear-to-l|background-image: linear-gradient(to left in oklab, var(--tw-gradient-stops))
    S bg-linear-to-tl|background-image: linear-gradient(to top left in oklab, var(--tw-gradient-stops))
    S blur-none|filter: ;
    S shadow-none|--tw-shadow: 0 0 #0000; --tw-shadow-colored: 0 0 #0000; box-shadow: var(--tw-ring-offset-shadow, 0 0 #0000), var(--tw-ring-shadow, 0 0 #0000), var(--tw-shadow)
    S decoration-clone|-webkit-box-decoration-break: clone; box-decoration-break: clone
    S decoration-slice|-webkit-box-decoration-break: slice; box-decoration-break: slice
    S flex-1|flex: 1 1 0%
    S flex-auto|flex: 1 1 auto
    S flex-initial|flex: 0 1 auto
    S flex-none|flex: none
    S table|display: table
    S contents|display: contents
    S flow-root|display: flow-root
    S list-item|display: list-item
    S grid|display: grid
    S flex|display: flex
    S block|display: block
    S inline|display: inline
    S inline-block|display: inline-block
    S inline-flex|display: inline-flex
    S inline-grid|display: inline-grid
    S inline-table|display: inline-table
    S table-caption|display: table-caption
    S table-cell|display: table-cell
    S table-column|display: table-column
    S table-column-group|display: table-column-group
    S table-footer-group|display: table-footer-group
    S table-header-group|display: table-header-group
    S table-row-group|display: table-row-group
    S table-row|display: table-row
    S static|position: static
    S fixed|position: fixed
    S absolute|position: absolute
    S relative|position: relative
    S sticky|position: sticky
    S mx-auto|margin-left: auto; margin-right: auto
    S pointer-events-none|pointer-events: none
    S pointer-events-auto|pointer-events: auto
    S bg-clip-text|-webkit-background-clip: text; background-clip: text
    S grid-cols-subgrid|grid-template-columns: subgrid
    S snap-mandatory|--tw-scroll-snap-strictness: mandatory
    S snap-proximity|--tw-scroll-snap-strictness: proximity
    S text-ellipsis|text-overflow: ellipsis
    S overflow-ellipsis|text-overflow: ellipsis
    S flex-grow|flex-grow: 1
    S flex-grow-0|flex-grow: 0
    S flex-shrink|flex-shrink: 1
    S flex-shrink-0|flex-shrink: 0
    S decoration-auto|text-decoration-thickness: auto
    S bg-origin-border|background-origin: border-box
    S bg-origin-padding|background-origin: padding-box
    S bg-origin-content|background-origin: content-box
    S text-clip|text-overflow: clip
    S text-wrap|text-wrap: wrap
    S text-nowrap|text-wrap: nowrap
    S text-balance|text-wrap: balance
    S text-pretty|text-wrap: pretty
    G text|text-align|left=left center=center right=right justify=justify start=start end=end
    G whitespace|white-space|normal=normal nowrap=nowrap pre=pre pre-line=pre-line pre-wrap=pre-wrap break-spaces=break-spaces
    G break|word-break|normal=normal all=break-all keep=keep-all
    S break-words|overflow-wrap: break-word
    S break-normal|overflow-wrap: normal; word-break: normal
    G float|float|left=left right=right none=none start=inline-start end=inline-end
    G clear|clear|left=left right=right both=both none=none start=inline-start end=inline-end
    G box|box-sizing|border=border-box content=content-box
    G object|object-fit|contain=contain cover=cover fill=fill none=none scale-down=scale-down
    G object|object-position|bottom=bottom center=center left=left left-bottom=left~bottom left-top=left~top right=right right-bottom=right~bottom right-top=right~top top=top
    G overflow|overflow|auto=auto hidden=hidden clip=clip visible=visible scroll=scroll
    G overflow-x|overflow-x|auto=auto hidden=hidden clip=clip visible=visible scroll=scroll
    G overflow-y|overflow-y|auto=auto hidden=hidden clip=clip visible=visible scroll=scroll
    G overscroll|overscroll-behavior|auto=auto contain=contain none=none
    G overscroll-x|overscroll-behavior-x|auto=auto contain=contain none=none
    G overscroll-y|overscroll-behavior-y|auto=auto contain=contain none=none
    G flex|flex-direction|row=row row-reverse=row-reverse col=column col-reverse=column-reverse
    G flex|flex-wrap|wrap=wrap wrap-reverse=wrap-reverse nowrap=nowrap
    G grow|flex-grow|0=0
    G shrink|flex-shrink|0=0
    G justify|justify-content|normal=normal start=flex-start end=flex-end center=center between=space-between around=space-around evenly=space-evenly stretch=stretch
    G justify-items|justify-items|start=start end=end center=center stretch=stretch
    G justify-self|justify-self|auto=auto start=start end=end center=center stretch=stretch
    G content|align-content|normal=normal center=center start=flex-start end=flex-end between=space-between around=space-around evenly=space-evenly baseline=baseline stretch=stretch
    G items|align-items|start=flex-start end=flex-end center=center baseline=baseline stretch=stretch
    G self|align-self|auto=auto start=flex-start end=flex-end center=center stretch=stretch baseline=baseline
    G place-content|place-content|center=center start=start end=end between=space-between around=space-around evenly=space-evenly baseline=baseline stretch=stretch
    G place-items|place-items|start=start end=end center=center baseline=baseline stretch=stretch
    G place-self|place-self|auto=auto start=start end=end center=center stretch=stretch
    G grid-flow|grid-auto-flow|row=row col=column dense=dense row-dense=row~dense col-dense=column~dense
    G auto-cols|grid-auto-columns|auto=auto min=min-content max=max-content fr=minmax(0,~1fr)
    G auto-rows|grid-auto-rows|auto=auto min=min-content max=max-content fr=minmax(0,~1fr)
    G list|list-style-type|none=none disc=disc decimal=decimal
    G list|list-style-position|inside=inside outside=outside
    G align|vertical-align|baseline=baseline top=top middle=middle bottom=bottom text-top=text-top text-bottom=text-bottom sub=sub super=super
    G decoration|text-decoration-style|solid=solid double=double dotted=dotted dashed=dashed wavy=wavy
    G border|border-style|solid=solid dashed=dashed dotted=dotted double=double hidden=hidden none=none
    G border|border-collapse|collapse=collapse separate=separate
    G divide|border-style|solid=solid dashed=dashed dotted=dotted double=double none=none
    G bg|background-attachment|fixed=fixed local=local scroll=scroll
    G bg-clip|background-clip|border=border-box padding=padding-box content=content-box
    G bg-origin|background-origin|border=border-box padding=padding-box content=content-box
    G bg|background-position|bottom=bottom center=center left=left left-bottom=left~bottom left-top=left~top right=right right-bottom=right~bottom right-top=right~top top=top
    G bg|background-repeat|repeat=repeat no-repeat=no-repeat repeat-x=repeat-x repeat-y=repeat-y repeat-round=round repeat-space=space
    G bg|background-size|auto=auto cover=cover contain=contain
    G bg-blend|background-blend-mode|normal=normal multiply=multiply screen=screen overlay=overlay darken=darken lighten=lighten color-dodge=color-dodge color-burn=color-burn hard-light=hard-light soft-light=soft-light difference=difference exclusion=exclusion hue=hue saturation=saturation color=color luminosity=luminosity
    G mix-blend|mix-blend-mode|normal=normal multiply=multiply screen=screen overlay=overlay darken=darken lighten=lighten color-dodge=color-dodge color-burn=color-burn hard-light=hard-light soft-light=soft-light difference=difference exclusion=exclusion hue=hue saturation=saturation color=color luminosity=luminosity plus-lighter=plus-lighter
    G table|table-layout|auto=auto fixed=fixed
    G caption|caption-side|top=top bottom=bottom
    G appearance|appearance|none=none auto=auto
    G cursor|cursor|auto=auto default=default pointer=pointer wait=wait text=text move=move help=help not-allowed=not-allowed none=none context-menu=context-menu progress=progress cell=cell crosshair=crosshair vertical-text=vertical-text alias=alias copy=copy no-drop=no-drop grab=grab grabbing=grabbing all-scroll=all-scroll col-resize=col-resize row-resize=row-resize n-resize=n-resize e-resize=e-resize s-resize=s-resize w-resize=w-resize ne-resize=ne-resize nw-resize=nw-resize se-resize=se-resize sw-resize=sw-resize ew-resize=ew-resize ns-resize=ns-resize nesw-resize=nesw-resize nwse-resize=nwse-resize zoom-in=zoom-in zoom-out=zoom-out
    G resize|resize|none=none y=vertical x=horizontal
    G scroll|scroll-behavior|auto=auto smooth=smooth
    G snap|scroll-snap-type|none=none
    G snap|scroll-snap-align|start=start end=end center=center align-none=none
    G snap|scroll-snap-stop|normal=normal always=always
    G touch|touch-action|auto=auto none=none pan-x=pan-x pan-left=pan-left pan-right=pan-right pan-y=pan-y pan-up=pan-up pan-down=pan-down pinch-zoom=pinch-zoom manipulation=manipulation
    G select|user-select|none=none text=text all=all auto=auto
    G will-change|will-change|auto=auto scroll=scroll-position contents=contents transform=transform
    G fill|fill|none=none
    G stroke|stroke|none=none
    G contain|contain|none=none content=content strict=strict size=size layout=layout paint=paint
    G content-visibility|content-visibility|auto=auto hidden=hidden visible=visible
    G forced-color-adjust|forced-color-adjust|auto=auto none=none
    G scheme|color-scheme|normal=normal dark=dark light=light light-dark=light~dark only-dark=only~dark only-light=only~light
    G field-sizing|field-sizing|content=content fixed=fixed
    G hyphens|hyphens|none=none manual=manual auto=auto
    G wrap|overflow-wrap|break-word=break-word anywhere=anywhere normal=normal
    G perspective-origin|perspective-origin|center=center top=top bottom=bottom left=left right=right
    G backface|backface-visibility|visible=visible hidden=hidden
    G origin|transform-origin|center=center top=top top-right=top~right right=right bottom-right=bottom~right bottom=bottom bottom-left=bottom~left left=left top-left=top~left
    """

    static let map: [String: [(String, String)]] = {
        var out: [String: [(String, String)]] = [:]
        func decls(_ s: String) -> [(String, String)] {
            s.split(separator: ";").compactMap { part in
                guard let c = part.firstIndex(of: ":") else { return nil }
                return (part[part.startIndex..<c].trimmingCharacters(in: .whitespaces), part[part.index(after: c)...].trimmingCharacters(in: .whitespaces))
            }
        }
        for line in table.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("S ") {
                let body = l.dropFirst(2)
                guard let bar = body.firstIndex(of: "|") else { continue }
                let name = String(body[body.startIndex..<bar])
                out[name] = decls(String(body[body.index(after: bar)...]))
            } else if l.hasPrefix("G ") {
                let p = l.dropFirst(2).split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
                guard p.count == 3, p[1] != "_" else { continue }
                for item in p[2].split(separator: " ") {
                    guard let eq = item.firstIndex(of: "=") else { continue }
                    let k = String(item[item.startIndex..<eq])
                    if k == "ignore" { continue }
                    let v = String(item[item.index(after: eq)...]).replacingOccurrences(of: "~", with: " ")
                    out[k == "_" ? p[0] : p[0] + "-" + k] = [(p[1], v)]
                }
            }
        }
        // explicit entries above win over generated ones that share a name
        for line in table.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("S "), let bar = l.firstIndex(of: "|") {
                out[String(l.dropFirst(2)[l.dropFirst(2).startIndex..<bar])] = decls(String(l[l.index(after: bar)...]))
            }
        }
        out["blur-none"] = [("--tw-blur", " "), ("filter", "var(--tw-blur) var(--tw-brightness) var(--tw-contrast) var(--tw-grayscale) var(--tw-hue-rotate) var(--tw-invert) var(--tw-saturate) var(--tw-sepia) var(--tw-drop-shadow)")]
        return out
    }()

    static let names: [String] = map.keys.sorted()
}
