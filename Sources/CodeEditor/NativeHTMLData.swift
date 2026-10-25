import Foundation

/// Static HTML knowledge: elements, attributes (global and per element), enumerated values, void / raw-text elements.
enum NWHtmlData {
    struct Tag { var name: String; var doc: String; var isVoid: Bool }

    private static let tagTable = """
    html|The root element of an HTML document.
    head|Machine-readable information about the document (title, scripts, styles).
    title|The document title shown in the browser tab.
    base|Base URL and default target for relative URLs.|void
    link|Relationship to an external resource (stylesheets, icons, preloads).|void
    meta|Metadata that cannot be expressed by other elements.|void
    style|Embedded CSS.
    script|Embedded or external script.
    noscript|Content shown when scripting is disabled.
    body|The content of the document.
    header|Introductory content or navigation links.
    nav|A section with navigation links.
    main|The dominant content of the document.
    section|A generic standalone section of the document.
    article|A self-contained composition.
    aside|Content indirectly related to the main content.
    footer|Footer for the nearest section or the document.
    h1|Top level heading.
    h2|Second level heading.
    h3|Third level heading.
    h4|Fourth level heading.
    h5|Fifth level heading.
    h6|Sixth level heading.
    hgroup|A heading with related content such as a subheading.
    address|Contact information for its nearest article or body.
    div|Generic block container with no semantics.
    p|A paragraph.
    span|Generic inline container with no semantics.
    a|Hyperlink to another page, a file, an email address or a location in the same page.
    br|A line break.|void
    hr|A thematic break between paragraph-level elements.|void
    pre|Preformatted text.
    blockquote|An extended quotation.
    q|A short inline quotation.
    cite|The title of a creative work.
    em|Stress emphasis.
    strong|Strong importance.
    small|Side comments such as small print.
    b|Draws attention without extra importance.
    i|Text in an alternate voice or mood.
    u|Unarticulated annotation (underline).
    s|Content that is no longer accurate.
    mark|Highlighted text for reference.
    code|A fragment of computer code.
    kbd|Keyboard input.
    samp|Sample output from a program.
    var|A variable in a mathematical expression or programming context.
    sub|Subscript.
    sup|Superscript.
    abbr|An abbreviation or acronym.
    dfn|The defining instance of a term.
    time|A specific period in time.
    data|Links content with a machine-readable translation.
    del|Text removed from the document.
    ins|Text added to the document.
    bdi|Isolates text for bidirectional formatting.
    bdo|Overrides the current text direction.
    wbr|A line break opportunity.|void
    ul|An unordered list.
    ol|An ordered list.
    li|A list item.
    dl|A description list.
    dt|A term in a description list.
    dd|The description of a term.
    menu|A set of commands.
    table|Tabular data.
    caption|The title of a table.
    colgroup|A group of columns in a table.
    col|A column in a table.|void
    thead|The header rows of a table.
    tbody|The body rows of a table.
    tfoot|The footer rows of a table.
    tr|A row of cells in a table.
    th|A header cell in a table.
    td|A data cell in a table.
    form|A document section containing interactive controls for submitting information.
    label|A caption for a form control.
    input|An interactive control for user data; its behavior depends on the type attribute.|void
    button|A clickable button.
    select|A control providing a menu of options.
    datalist|Predefined options for an input.
    optgroup|A group of options in a select.
    option|An option in a select, optgroup or datalist.
    textarea|A multi-line plain text editing control.
    output|The result of a calculation or user action.
    progress|The completion progress of a task.
    meter|A scalar measurement within a known range.
    fieldset|A group of form controls.
    legend|The caption of a fieldset.
    img|Embeds an image.|void
    picture|Container for multiple image sources.
    source|A media resource for picture, audio or video.|void
    video|Embeds a media player for video.
    audio|Embeds a sound player.
    track|Timed text track for video and audio.|void
    iframe|Embeds another HTML page.
    embed|Embeds external content.|void
    object|An external resource (image, nested browsing context, plugin).
    canvas|A container for graphics drawn with scripts.
    svg|An embedded SVG graphic.
    math|An embedded MathML formula.
    map|Defines an image map.
    area|A hot-spot region on an image map.|void
    figure|Self-contained content with an optional caption.
    figcaption|A caption for a figure.
    details|A disclosure widget.
    summary|The visible heading of a details element.
    dialog|A dialog box or window.
    template|Content not rendered when the page loads (cloned by scripts).
    slot|A placeholder inside a web component.
    search|A section containing search or filtering controls.
    ruby|Ruby annotations for East Asian typography.
    rt|The ruby text component.
    rp|Fallback parentheses for ruby.
    portal|Embeds another page (deprecated).
    center|Centers content (obsolete).
    font|Font styling (obsolete).
    marquee|Scrolling content (obsolete).
    """

    static let tags: [Tag] = tagTable.split(separator: "\n").compactMap { line in
        let p = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard p.count >= 2 else { return nil }
        return Tag(name: p[0], doc: p[1], isVoid: p.count > 2 && p[2] == "void")
    }
    static let tagMap: [String: Tag] = Dictionary(uniqueKeysWithValues: tags.map { ($0.name, $0) })
    static let voidTags: Set<String> = Set(tags.filter(\.isVoid).map(\.name))
    static let rawTextTags: Set<String> = ["script", "style", "textarea", "title"]

    // MARK: attributes

    struct Attr { var name: String; var doc: String; var values: [String] }

    private static let globalTable = """
    id|Unique identifier of the element.
    class|Space separated list of the element's classes.
    style|Inline CSS declarations.
    title|Advisory information shown as a tooltip.
    lang|Language of the element's content.
    dir|Text direction.|ltr rtl auto
    hidden|Hides the element (it is not rendered).|hidden until-found
    tabindex|Whether and in which order the element takes part in sequential focus navigation.
    accesskey|Keyboard shortcut for the element.
    draggable|Whether the element can be dragged.|true false
    contenteditable|Whether the element is editable.|true false plaintext-only
    spellcheck|Whether the element is checked for spelling.|true false
    translate|Whether the content is translated with the page.|yes no
    inert|Makes the element and its subtree non-interactive.
    autofocus|Focuses the element when the page loads.
    autocapitalize|Capitalization of user input.|off none on sentences words characters
    enterkeyhint|Label of the enter key on virtual keyboards.|enter done go next previous search send
    inputmode|Which virtual keyboard to show.|none text decimal numeric tel search email url
    is|Name of a customized built-in element.
    nonce|Cryptographic nonce used by CSP.
    popover|Marks the element as a popover.|auto manual
    slot|Name of the slot the element is assigned to.
    part|Names the element for ::part() styling.
    role|ARIA role.|alert alertdialog application article banner button cell checkbox columnheader combobox complementary contentinfo definition dialog directory document feed figure form grid gridcell group heading img link list listbox listitem log main marquee math menu menubar menuitem menuitemcheckbox menuitemradio navigation none note option presentation progressbar radio radiogroup region row rowgroup rowheader scrollbar search searchbox separator slider spinbutton status switch tab table tablist tabpanel term textbox timer toolbar tooltip tree treegrid treeitem
    itemprop|Microdata property name.
    itemscope|Creates a microdata item.
    itemtype|Microdata item type URL.
    """

    static let globalAttrs: [Attr] = parseAttrs(globalTable)

    private static func parseAttrs(_ s: String) -> [Attr] {
        s.split(separator: "\n").compactMap { line in
            let p = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard p.count >= 2, !p[0].isEmpty else { return nil }
            return Attr(name: p[0], doc: p[1], values: p.count > 2 ? p[2].split(separator: " ").map(String.init) : [])
        }
    }

    static let eventHandlers: [String] = ["onclick", "ondblclick", "onchange", "oninput", "onsubmit", "onreset", "onfocus", "onblur", "onkeydown", "onkeyup", "onkeypress",
                                          "onmousedown", "onmouseup", "onmouseover", "onmouseout", "onmouseenter", "onmouseleave", "onmousemove", "onload", "onerror", "onscroll",
                                          "onresize", "oncontextmenu", "onwheel", "ondrag", "ondragstart", "ondragend", "ondragover", "ondrop", "ontouchstart", "ontouchend",
                                          "oncopy", "oncut", "onpaste", "onselect", "oninvalid", "ontoggle", "onanimationend", "ontransitionend", "onplay", "onpause", "onended"]

    static let ariaAttrs: [String] = ["aria-label", "aria-labelledby", "aria-describedby", "aria-hidden", "aria-expanded", "aria-controls", "aria-live", "aria-atomic", "aria-busy",
                                      "aria-checked", "aria-current", "aria-disabled", "aria-haspopup", "aria-invalid", "aria-modal", "aria-multiline", "aria-multiselectable",
                                      "aria-orientation", "aria-pressed", "aria-readonly", "aria-required", "aria-selected", "aria-sort", "aria-valuemax", "aria-valuemin",
                                      "aria-valuenow", "aria-valuetext", "aria-activedescendant", "aria-autocomplete", "aria-owns", "aria-placeholder", "aria-posinset",
                                      "aria-setsize", "aria-level", "aria-colcount", "aria-rowcount", "aria-errormessage", "aria-details", "aria-keyshortcuts", "aria-roledescription"]

    private static let elementTable: [String: String] = [
        "a": "href|The URL of the link.\ntarget|Where to display the linked URL.|_self _blank _parent _top\nrel|Relationship of the linked URL.|noopener noreferrer nofollow external noreferrer\ndownload|Downloads the URL instead of navigating.\nhreflang|Language of the linked resource.\ntype|MIME type of the linked resource.\nreferrerpolicy|Referrer to send.|no-referrer origin same-origin strict-origin strict-origin-when-cross-origin unsafe-url\nping|URLs to ping.",
        "img": "src|The image URL.\nalt|Alternative text.\nsrcset|Candidate image sources.\nsizes|Source sizes for srcset.\nwidth|Intrinsic width.\nheight|Intrinsic height.\nloading|Loading strategy.|lazy eager\ndecoding|Decoding hint.|async sync auto\nfetchpriority|Fetch priority hint.|high low auto\ncrossorigin|CORS setting.|anonymous use-credentials\nreferrerpolicy|Referrer to send.|no-referrer origin same-origin strict-origin\nusemap|Image map name.\nismap|Server side image map.",
        "input": "type|Control type.|text password email number tel url search date time datetime-local month week color range file checkbox radio hidden submit reset button image\nname|Name submitted with the form.\nvalue|Current value.\nplaceholder|Hint shown when empty.\nrequired|Value is required.\ndisabled|Disables the control.\nreadonly|Value cannot be edited.\nchecked|Checkbox or radio is checked.\nmin|Minimum value.\nmax|Maximum value.\nstep|Granularity of the value.\nminlength|Minimum length.\nmaxlength|Maximum length.\npattern|Regular expression the value must match.\nmultiple|Allows multiple values.\naccept|Accepted file types.\nautocomplete|Autofill hint.|on off name email username new-password current-password one-time-code tel street-address postal-code country cc-number\nlist|Id of a datalist.\nsize|Visible width in characters.\nform|Id of the owning form.\nformaction|Overrides the form's action.\nformmethod|Overrides the form's method.|get post dialog\nfor|Id of the labelled control.\ncapture|Capture source for file inputs.|user environment\nalt|Alt text for image inputs.\nsrc|Image URL for image inputs.\nwidth|Width of image inputs.\nheight|Height of image inputs.",
        "button": "type|Button behavior.|submit reset button\nname|Name submitted with the form.\nvalue|Value submitted with the form.\ndisabled|Disables the button.\nform|Id of the owning form.\nformaction|Overrides the form's action.\nformmethod|Overrides the form's method.|get post dialog\nformtarget|Overrides the form's target.|_self _blank _parent _top\npopovertarget|Id of the popover to control.\npopovertargetaction|Action on the popover.|toggle show hide",
        "form": "action|URL that processes the submission.\nmethod|HTTP method.|get post dialog\nenctype|Encoding of submitted data.|application/x-www-form-urlencoded multipart/form-data text/plain\ntarget|Where to display the response.|_self _blank _parent _top\nnovalidate|Skips validation on submit.\nautocomplete|Autofill hint.|on off\nname|Name of the form.\nrel|Link relationship.\naccept-charset|Accepted character encodings.",
        "label": "for|Id of the labelled control.\nform|Id of the owning form.",
        "select": "name|Name submitted with the form.\nmultiple|Allows multiple selections.\nrequired|A selection is required.\ndisabled|Disables the control.\nsize|Number of visible rows.\nautocomplete|Autofill hint.\nform|Id of the owning form.",
        "option": "value|Value submitted.\nselected|Preselects the option.\ndisabled|Disables the option.\nlabel|Label of the option.",
        "textarea": "name|Name submitted with the form.\nrows|Visible lines.\ncols|Visible columns.\nplaceholder|Hint shown when empty.\nrequired|Value is required.\ndisabled|Disables the control.\nreadonly|Value cannot be edited.\nmaxlength|Maximum length.\nminlength|Minimum length.\nwrap|Wrapping of submitted text.|soft hard off\nautocomplete|Autofill hint.\nform|Id of the owning form.",
        "link": "rel|Relationship to the resource.|stylesheet icon preload prefetch preconnect dns-prefetch modulepreload canonical alternate manifest apple-touch-icon\nhref|The URL of the resource.\nas|Type of a preloaded resource.|script style font image fetch document audio video track worker\ntype|MIME type of the resource.\nmedia|Media query the resource applies to.\nsizes|Icon sizes.\ncrossorigin|CORS setting.|anonymous use-credentials\nintegrity|Subresource integrity hash.\nhreflang|Language of the resource.\nfetchpriority|Fetch priority hint.|high low auto\ndisabled|Disables the stylesheet.",
        "meta": "name|Metadata name.|viewport description keywords author robots theme-color color-scheme generator referrer application-name\ncontent|Metadata value.\ncharset|Document encoding.|utf-8\nhttp-equiv|Pragma directive.|content-type refresh content-security-policy x-ua-compatible default-style\nproperty|Open Graph property.\nmedia|Media query for theme-color.",
        "script": "src|URL of an external script.\ntype|Script type.|module text/javascript importmap application/json application/ld+json speculationrules\nasync|Executes as soon as it is available.\ndefer|Executes after parsing.\ncrossorigin|CORS setting.|anonymous use-credentials\nintegrity|Subresource integrity hash.\nnomodule|Skipped by module-supporting browsers.\nreferrerpolicy|Referrer to send.\nfetchpriority|Fetch priority hint.|high low auto",
        "style": "media|Media query the styles apply to.\ntype|Style language.\nnonce|CSP nonce.",
        "iframe": "src|URL of the page to embed.\nsrcdoc|Inline HTML to embed.\nname|Name of the browsing context.\nwidth|Width.\nheight|Height.\nloading|Loading strategy.|lazy eager\nallow|Permissions policy.\nallowfullscreen|Allows fullscreen.\nsandbox|Sandbox restrictions.|allow-forms allow-modals allow-popups allow-same-origin allow-scripts allow-top-navigation\nreferrerpolicy|Referrer to send.\ntitle|Accessible title.",
        "video": "src|URL of the video.\ncontrols|Shows playback controls.\nautoplay|Starts playing automatically.\nloop|Restarts at the end.\nmuted|Silences audio.\nplaysinline|Plays inline on iOS.\npreload|Loading hint.|none metadata auto\nposter|Image shown before playback.\nwidth|Width.\nheight|Height.\ncrossorigin|CORS setting.|anonymous use-credentials",
        "audio": "src|URL of the audio.\ncontrols|Shows playback controls.\nautoplay|Starts playing automatically.\nloop|Restarts at the end.\nmuted|Silences audio.\npreload|Loading hint.|none metadata auto\ncrossorigin|CORS setting.|anonymous use-credentials",
        "source": "src|URL of the media resource.\nsrcset|Candidate image sources.\ntype|MIME type.\nmedia|Media query.\nsizes|Source sizes.\nwidth|Width.\nheight|Height.",
        "track": "src|URL of the track.\nkind|Kind of track.|subtitles captions descriptions chapters metadata\nsrclang|Language of the track.\nlabel|User visible title.\ndefault|Enables the track by default.",
        "td": "colspan|Number of columns spanned.\nrowspan|Number of rows spanned.\nheaders|Ids of related header cells.",
        "th": "colspan|Number of columns spanned.\nrowspan|Number of rows spanned.\nscope|Cells the header applies to.|row col rowgroup colgroup\nheaders|Ids of related header cells.\nabbr|Short description.",
        "col": "span|Number of columns spanned.", "colgroup": "span|Number of columns spanned.",
        "ol": "start|First number.\nreversed|Counts down.\ntype|Marker type.|1 a A i I",
        "li": "value|Ordinal value of the item.",
        "details": "open|Shows the details.\nname|Group name for exclusive accordions.",
        "dialog": "open|Shows the dialog.",
        "canvas": "width|Width.\nheight|Height.",
        "svg": "viewBox|Position and dimension of the viewport.\nxmlns|XML namespace.\nwidth|Width.\nheight|Height.\nfill|Fill color.\nstroke|Stroke color.\nstroke-width|Stroke width.\npreserveAspectRatio|Aspect ratio handling.",
        "progress": "value|Current value.\nmax|Maximum value.", "meter": "value|Current value.\nmin|Lower bound.\nmax|Upper bound.\nlow|Low threshold.\nhigh|High threshold.\noptimum|Optimal value.",
        "time": "datetime|Machine-readable date or time.", "data": "value|Machine-readable value.",
        "blockquote": "cite|URL of the quotation source.", "q": "cite|URL of the quotation source.",
        "del": "cite|URL explaining the change.\ndatetime|Time of the change.", "ins": "cite|URL explaining the change.\ndatetime|Time of the change.",
        "fieldset": "disabled|Disables descendant controls.\nname|Name of the group.\nform|Id of the owning form.",
        "optgroup": "label|Name of the group.\ndisabled|Disables the group.",
        "output": "for|Ids of the controls contributing to the result.\nname|Name of the output.\nform|Id of the owning form.",
        "area": "shape|Shape of the region.|rect circle poly default\ncoords|Coordinates of the region.\nhref|The URL of the link.\nalt|Alternative text.",
        "map": "name|Name of the map.", "base": "href|Base URL.\ntarget|Default target.|_self _blank _parent _top",
        "html": "lang|Language of the document.\nxmlns|XML namespace.", "template": "shadowrootmode|Declarative shadow root mode.|open closed",
        "object": "data|URL of the resource.\ntype|MIME type.\nwidth|Width.\nheight|Height.\nname|Name.", "embed": "src|URL of the resource.\ntype|MIME type.\nwidth|Width.\nheight|Height.",
    ]

    private static var attrCache: [String: [Attr]] = [:]
    private static let lock = NSLock()

    static func attrs(for tag: String) -> [Attr] {
        let t = tag.lowercased()
        lock.lock(); defer { lock.unlock() }
        if let c = attrCache[t] { return c }
        let parsed = elementTable[t].map(parseAttrs) ?? []
        attrCache[t] = parsed
        return parsed
    }

    static func attr(_ name: String, tag: String) -> Attr? {
        let n = name.lowercased()
        return attrs(for: tag).first { $0.name.lowercased() == n } ?? globalAttrs.first { $0.name == n }
    }

    static func dropCaches() { lock.lock(); attrCache.removeAll(); lock.unlock() }

    // MARK: framework attribute names (offered only when the file kind makes them likely)

    static let vueAttrs: [(String, String)] = [("v-if", "Conditionally renders the element."), ("v-else-if", "Else-if branch of v-if."), ("v-else", "Else branch of v-if."),
                                               ("v-for", "Renders the element once per item."), ("v-model", "Two-way binding on a form input or component."),
                                               ("v-show", "Toggles the element's display."), ("v-bind", "Binds an attribute to an expression."), ("v-on", "Attaches an event listener."),
                                               ("v-html", "Sets the element's innerHTML."), ("v-text", "Sets the element's text."), ("v-slot", "Names a slot."),
                                               ("v-once", "Renders once."), ("v-pre", "Skips compilation."), ("v-cloak", "Hidden until compiled."), ("v-memo", "Memoizes a subtree."),
                                               (":class", "Binds the class attribute."), (":style", "Binds the style attribute."), (":key", "Special key for diffing."),
                                               ("@click", "Click listener."), ("@input", "Input listener."), ("@change", "Change listener."), ("@submit.prevent", "Submit listener that prevents the default."),
                                               ("ref", "Template ref."), ("key", "Special key for diffing.")]
    static let alpineAttrs: [String] = ["x-data", "x-show", "x-if", "x-for", "x-model", "x-text", "x-html", "x-bind", "x-on", "x-init", "x-ref", "x-cloak", "x-transition", "@click"]
    static let livewireAttrs: [String] = ["wire:click", "wire:model", "wire:model.live", "wire:submit", "wire:submit.prevent", "wire:loading", "wire:target", "wire:key", "wire:poll", "wire:init", "wire:navigate"]
}
