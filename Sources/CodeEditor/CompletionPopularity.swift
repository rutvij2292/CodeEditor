import Foundation

/// A tiny static "what do people actually type" prior: names ordered most-used first. The ranker uses it only to order
/// otherwise equal candidates (same match class, same familiarity, same provider tier), so `str_ends_with` beats `str_word_count`
/// for `st`, `@endforeach` beats `@endauth` for `@en`, `v-if` beats `v-bind` for `v-`. ~600 short strings, built lazily per file type.
enum CompletionPopularity {
    private static let lists: [String: String] = [
        "php": """
        count isset empty in_array array_map array_filter implode explode str_replace strlen json_encode json_decode array_merge array_keys array_values \
        array_key_exists sprintf number_format date strtotime trim strtolower strtoupper substr strpos str_contains str_starts_with str_ends_with is_null \
        is_array is_string is_numeric is_int intval floatval round floor ceil max min abs array_sum array_unique array_reverse array_slice array_splice \
        array_search array_column array_combine array_flip array_diff array_intersect array_push array_pop array_shift array_unshift array_reduce \
        array_walk usort sort ksort rsort asort arsort preg_match preg_replace preg_split preg_match_all preg_quote ucfirst ucwords lcfirst str_pad \
        str_repeat str_split nl2br htmlspecialchars strip_tags md5 sha1 hash base64_encode base64_decode uniqid rand mt_rand random_int file_get_contents \
        file_put_contents file_exists is_file is_dir mkdir unlink basename dirname pathinfo realpath fopen fclose fwrite fgets mb_strlen mb_substr \
        mb_strtolower mb_strtoupper var_dump print_r var_export dd dump compact extract call_user_func call_user_func_array function_exists \
        method_exists class_exists property_exists get_class iterator_to_array array_key_first array_key_last array_fill array_fill_keys range \
        array_chunk array_pad array_rand shuffle array_is_list strcmp strrev substr_count ltrim rtrim wordwrap array_diff_key array_intersect_key \
        array_replace array_multisort array_walk_recursive date_default_timezone_set time microtime mktime checkdate gmdate is_bool is_float is_object \
        is_callable is_iterable is_countable boolval strval settype gettype serialize unserialize urlencode rawurlencode http_build_query parse_str \
        parse_url filter_var password_hash password_verify openssl_encrypt openssl_decrypt random_bytes bin2hex hex2bin ctype_digit ctype_alpha \
        config route view auth request response redirect session cache collect now today optional tap value abort abort_if abort_unless back bcrypt \
        csrf_token old url asset app env event dispatch logger info report rescue resolve retry throw_if throw_unless trans __ validator data_get \
        data_set head last blank filled str e class_basename storage_path base_path public_path resource_path app_path database_path config_path \
        method_field csrf_field to_route policy broadcast cookie literal fake precognitive \
        Exception InvalidArgumentException RuntimeException DateTime DateTimeImmutable Carbon Collection Request Response Model Builder Validator Log Cache DB Auth Storage \
        Str Arr Http Route Schema Config Session Cookie Hash Mail Queue Event Gate URL Redirect View File Lang Blade Artisan Password Process Pipeline Bus Notification \
        Crypt Date Redis Number Sleep Context TypeError ValueError JsonException Throwable Closure ArrayObject ArrayIterator Countable Stringable JsonSerializable \
        Traversable Iterator Generator SplFileInfo PDO PDOException DOMDocument ReflectionClass LogicException DomainException OutOfBoundsException UnexpectedValueException
        """,
        "eloquent": """
        where get first find findOrFail firstOrFail create update delete save with orderBy latest oldest paginate count exists pluck select whereIn whereNull \
        whereNotNull whereBetween orWhere firstOrCreate updateOrCreate firstWhere groupBy having join leftJoin limit take skip offset value sum max min avg \
        query all toArray toJson load loadMissing withCount withTrashed onlyTrashed restore forceDelete whereHas has doesntHave whereDate whereMonth \
        whereYear whereRaw selectRaw orderByDesc orderByRaw distinct chunk each map filter reject sortBy sortByDesc values keys flatten merge push put \
        forget contains isEmpty isNotEmpty reduce unique keyBy only except fresh refresh increment decrement insert upsert truncate when unless tap \
        toSql dd dump cursor lazy findMany pluck sole whereNotIn whereNot whereColumn whereExists whereLike whereAny orWhereIn rightJoin crossJoin \
        union lockForUpdate sharedLock inRandomOrder reorder addSelect fromSub joinSub chunkById lazyById exists doesntExist first last implode \
        sortKeys groupBy mapWithKeys flatMap zip pipe partition slice splice reverse shift pop prepend pull random shuffle sum avg median mode \
        countBy diff intersect isDirty isClean wasChanged getOriginal fill forceFill replicate is isNot getKey getKeyName getTable touch belongsTo \
        hasMany hasOne belongsToMany morphTo morphMany hasManyThrough hasOneThrough attach detach sync syncWithoutDetaching toggle updateExistingPivot
        """,
        "blade": """
        if foreach endforeach endif else elseif section endsection yield extends include component endcomponent auth endauth guest endguest csrf method \
        error enderror isset endisset empty endempty forelse endforelse empty for endfor while endwhile php endphp push endpush stack props slot endslot \
        once can endcan cannot endcannot lang json vite inertia inertiaHead class unless endunless switch case break default endswitch includeIf \
        includeWhen includeUnless includeFirst each prepend endprepend parent show verbatim endverbatim env endenv production endproduction session \
        endsession pushOnce endPushOnce pushIf livewire livewireStyles livewireScripts click style checked selected disabled readonly required continue \
        aware use dd dump fragment endfragment hasSection sectionMissing canany elsecan elsecannot elseauth elseguest teleport
        """,
        "js": """
        log map filter forEach push length includes find join slice split replace trim toString keys values entries assign stringify parse then catch \
        finally isArray resolve all floor round max min abs random indexOf concat reduce some every sort splice pop shift unshift flat flatMap from \
        toFixed startsWith endsWith substring toLowerCase toUpperCase padStart padEnd error warn info table getElementById querySelector querySelectorAll \
        addEventListener removeEventListener createElement appendChild classList setAttribute getAttribute preventDefault stopPropagation value target \
        querySelector getElementById fetch json status text blob ok headers body setTimeout setInterval clearTimeout clearInterval parseInt parseFloat isNaN isFinite Number String \
        Boolean Array Object Promise JSON Math Date Map Set RegExp Error window document console localStorage sessionStorage getItem setItem removeItem \
        ref reactive computed watch watchEffect onMounted onUnmounted onBeforeMount onUpdated defineProps defineEmits defineExpose nextTick toRef toRefs \
        useRouter useRoute provide inject h createApp useSlots useAttrs defineModel shallowRef triggerRef unref isRef emit props slots \
        useState useEffect useRef useCallback useMemo useContext useReducer createContext memo forwardRef lazy Suspense Fragment \
        require module exports import export default async await const let function return class extends constructor new this super \
        add delete has get set clear size forEach charAt charCodeAt codePointAt match matchAll search at fill findIndex findLast lastIndexOf reverse \
        toSorted toReversed with groupBy fromEntries hasOwn freeze seal create defineProperty getPrototypeOf setPrototypeOf getOwnPropertyNames \
        allSettled race any reject withResolvers toISOString toLocaleDateString toLocaleString toLocaleTimeString getTime getFullYear getMonth getDate \
        now UTC floor ceil trunc sign sqrt pow PI cos sin tan log10 hypot cbrt style innerHTML textContent innerText dataset children parentElement \
        closest matches remove append prepend before after insertBefore cloneNode contains focus blur click submit reset dispatchEvent scrollIntoView \
        getBoundingClientRect offsetWidth offsetHeight clientWidth clientHeight scrollTop scrollHeight scrollTo location href pathname search hash origin \
        reload replace assign history pushState replaceState back forward navigator userAgent clipboard writeText readText
        """,
        "vue": """
        v-if v-for v-model v-show v-bind v-on v-else v-else-if v-slot v-html v-text v-once v-pre v-cloak v-memo :key :class :style :disabled :value :src \
        :href :to :id :title :placeholder :type :checked :selected :readonly :required :label :options :items :modelValue :loading :visible \
        @click @input @change @submit @keyup @keydown @blur @focus @update:modelValue @mouseover @mouseleave @scroll @close @select @confirm @cancel @save \
        template script setup scoped style slot component transition keep-alive teleport suspense router-link router-view
        """,
        "py": """
        print len range str int list dict set tuple open isinstance enumerate zip sorted sum min max abs any all map filter super type float bool input \
        getattr setattr hasattr round reversed format repr id iter next callable chr ord hex bin divmod pow vars dir globals locals property staticmethod \
        classmethod object Exception ValueError TypeError KeyError IndexError RuntimeError AttributeError NotImplementedError StopIteration OSError \
        ImportError FileNotFoundError PermissionError TimeoutError ZeroDivisionError AssertionError Warning \
        append extend items keys values get join split strip format replace startswith endswith lower upper pop update sort remove insert index count \
        copy clear add discard encode decode find splitlines lstrip rstrip title capitalize isdigit isalpha isalnum islower isupper zfill center ljust rjust \
        setdefault popitem fromkeys union intersection difference issubset issuperset symmetric_difference reverse rfind rsplit partition \
        os sys json re datetime typing pathlib collections itertools functools logging asyncio math random time subprocess dataclasses enum abc uuid \
        hashlib base64 copy io csv argparse shutil tempfile threading multiprocessing socket sqlite3 urllib http contextlib inspect traceback warnings \
        FastAPI APIRouter Depends HTTPException Request Response status Query Path Body BackgroundTasks Header Cookie File UploadFile Form Security \
        JSONResponse HTMLResponse RedirectResponse StreamingResponse FileResponse CORSMiddleware BaseModel Field validator field_validator ConfigDict \
        List Dict Optional Union Any Tuple Set Callable Iterable Iterator Generator TypeVar Generic Literal Annotated Type ClassVar Final Protocol \
        dataclass field asdict astuple namedtuple defaultdict Counter OrderedDict deque ChainMap partial wraps lru_cache cache reduce cached_property \
        Path glob mkdir exists is_file is_dir read_text write_text read_bytes write_bytes iterdir resolve parent stem suffix name parts \
        self cls __init__ __str__ __repr__ __name__ __main__ __file__ __all__ __dict__ __class__ __doc__ __enter__ __exit__ __call__ __len__ __iter__ \
        __getitem__ __setitem__ __eq__ __hash__ __lt__ __contains__ __post_init__ __slots__ __version__ __new__ __del__ __bool__ __add__ \
        requests numpy pandas fastapi pydantic sqlalchemy uvicorn pytest flask django httpx aiohttp scipy matplotlib torch transformers sklearn openai dotenv yaml \
        jinja2 click typer rich tqdm redis celery boto3 psycopg2 pymongo qdrant_client sentence_transformers \
        getenv environ path exists makedirs listdir getcwd now isoformat strftime strptime timedelta timezone utc fromisoformat today dumps loads dump load compile \
        match search sub findall argv exit stdout stderr status_code text headers raise_for_status getLogger debug warning exception randint choice sample uniform \
        sleep perf_counter monotonic sqrt floor ceil pi run gather create_task
        """,
        "css": """
        display margin padding width height color background border position font-size font-weight text-align flex justify-content align-items border-radius \
        background-color overflow z-index top left right bottom max-width min-width max-height min-height margin-top margin-bottom margin-left margin-right \
        padding-top padding-bottom padding-left padding-right cursor opacity transition transform box-shadow line-height font-family text-decoration \
        border-color border-width border-style border-bottom border-top border-left border-right background-image background-size background-position \
        background-repeat font-style text-decoration text-transform letter-spacing white-space overflow overflow-x \
        overflow-y opacity cursor flex flex-direction flex-wrap flex-grow flex-shrink flex-basis justify-content align-items align-self align-content gap \
        row-gap column-gap grid grid-template-columns grid-template-rows grid-column grid-row box-shadow transition transform animation content visibility \
        float clear box-sizing outline list-style vertical-align object-fit pointer-events user-select resize appearance filter backdrop-filter will-change \
        text-overflow word-break word-wrap text-shadow transform-origin animation-name animation-duration transition-property transition-duration \
        transition-timing-function inset order aspect-ratio place-items place-content text-indent fill stroke clip-path mask scroll-behavior \
        flex block none inline-block inline grid inline-flex absolute relative fixed sticky static center space-between space-around space-evenly flex-start \
        flex-end nowrap wrap hidden auto pointer bold normal uppercase lowercase capitalize solid dashed dotted transparent inherit initial unset column row \
        stretch baseline cover contain no-repeat repeat scroll visible collapse underline italic ellipsis break-word pre pre-wrap not-allowed
        """,
        "tw": """
        flex items-center justify-between w-full h-full p-4 px-4 py-2 mb-4 mt-4 text-sm font-bold font-semibold font-medium bg-white text-gray-500 text-gray-700 \
        text-gray-900 rounded rounded-lg border shadow hidden block relative absolute grid gap-2 gap-4 space-x-2 space-y-2 min-h-screen container mx-auto \
        overflow-hidden cursor-pointer transition text-center text-white text-lg text-xl text-2xl px-2 py-1 py-4 px-6 py-3 mt-2 mb-2 ml-2 mr-2 mt-1 mb-1 p-2 p-6 \
        flex-col flex-1 flex-wrap justify-center justify-end items-start items-end w-1/2 w-auto h-screen h-auto max-w-md max-w-xl max-w-7xl truncate uppercase \
        font-normal font-light text-xs text-base text-black text-gray-600 text-gray-800 text-gray-400 text-red-500 text-blue-600 text-green-600 bg-gray-50 bg-gray-100 \
        bg-gray-200 bg-blue-500 bg-blue-600 bg-red-500 bg-green-500 border-gray-200 border-gray-300 border-b border-t rounded-md rounded-full shadow-sm shadow-md \
        hover:bg-gray-100 hover:text-blue-600 focus:outline-none focus:ring-2 sm:px-6 md:flex md:w-1/2 lg:px-8 dark:bg-gray-800 dark:text-white fixed sticky inset-0 \
        top-0 left-0 right-0 bottom-0 z-10 z-50 opacity-50 pointer-events-none select-none whitespace-nowrap leading-tight tracking-wide underline line-through \
        object-cover aspect-square animate-spin ring-1 divide-y sr-only col-span-2 grid-cols-2 grid-cols-3 order-1 self-center place-items-center
        """,
        "html": """
        class id style href src type name value placeholder alt title for action method target rel disabled required checked selected readonly width height \
        data- aria-label role tabindex onclick autocomplete min max step rows cols colspan rowspan maxlength pattern multiple accept charset content lang \
        hidden draggable loading download enctype autofocus aria-hidden aria-expanded aria-controls
        """,
    ]

    /// Entries closer than this are treated as equally popular (the list order inside a bucket is guesswork; shorter names win there).
    private static let bucket = 10
    /// Short, carefully ordered lists keep their exact order.
    private static let bucketByGroup: [String: Int] = ["html": 1, "blade": 3, "vue": 2, "tw": 5]

    private static var cache: [String: [String: Int]] = [:]
    private static let lock = NSLock()

    /// Which lists apply to a file.
    private static func groups(ext: String, blade: Bool) -> [String] {
        switch ext {
        case "php", "phtml": return blade ? ["blade", "php", "eloquent", "html", "tw", "css", "js"] : ["php", "eloquent"]
        case "vue": return ["js", "vue", "html", "tw", "css"]
        case "js", "jsx", "ts", "tsx", "mjs", "cjs": return ["js", "tw"]
        case "py", "pyi", "pyw": return ["py"]
        case "css", "scss", "less", "sass", "pcss": return ["css"]
        case "html", "htm": return ["html", "vue", "tw", "css", "js"]
        default: return []
        }
    }

    /// name -> rank (0 = most popular) for a file type; empty for others. Cached per file type.
    static func table(ext: String, blade: Bool) -> [String: Int] {
        let e = ext.lowercased()
        let key = e + (blade ? "+blade" : "")
        lock.lock(); defer { lock.unlock() }
        if let t = cache[key] { return t }
        var t: [String: Int] = [:]
        for g in groups(ext: e, blade: blade) {
            guard let list = lists[g] else { continue }
            var i = 0
            let size = bucketByGroup[g] ?? bucket
            for w in list.split(whereSeparator: { $0 == " " || $0 == "\n" }) where w != "\\" {
                let k = String(w)
                if t[k] == nil { t[k] = i / size }
                i += 1
            }
        }
        cache[key] = t
        return t
    }
}
