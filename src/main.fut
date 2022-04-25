module sort = import "radix_sort"

let chunks: i64 = 16

-- Timestamps are of form '2009-06-08 21:49:38', 19 chars
let timestamp_length = 19i64

-- According to twitter, handles can be 15 characters: alphanumeric and _
-- Officially, these include uppercase letters as well, however from the
-- dataset it seems that these do not exist
let username_max_length = 15i64

type Username = [username_max_length]u8

let username_eq (a: Username) (b: Username): bool = all id (map2 (==) a b)

let username_lte (a: Username) (b: Username): bool =
    let i =
        iterate_until
            (\i -> i == username_max_length || a[i] != b[i])
            (+1)
            0
    in i == username_max_length || a[i] < b[i]

let is_allowed_in_username (c: u8): bool =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'

let is_mention_delimiter (c: u8): bool =
    c != '@' && !(is_allowed_in_username c)

let is_mention_start (text: []u8) (i: i64): bool =
    -- text[i - 1] is valid as an @ shouldn't be outside of tweet text,
    -- and a tab is also a mention delimiter
    text[i] == '@' && is_mention_delimiter text[i - 1]

let shift [n] 't (value: t) (items: *[n]t) : *[n]t =
    (rotate (-1i64) items) with [0] = value

let binary_search [n] 't (lte: t -> t -> bool) (items: [n]t) (key: t): i64 =
    let (l, _) =
        loop (l, r) = (0, n - 1) while l < r do
            let m = l + (r - l) / 2
            in if key `lte` items[m]
                then (l, m)
                else (m + 1, r)
    in if items[l] `lte` key
        then l
        else -1

-- Ceil division
let (l: i64) /^ (r: i64) = (l + r - 1) / r

let deduplicate [n] 't (eq: t -> t -> bool) (items: *[n]t) : *[]t =
    let m = n - 1
    let is_duplicate = [false] ++ (map2 eq (items[1:n] :> [m]t) (items[0:n-1] :> [m]t))
    let is = filter
        (\i -> !is_duplicate[i])
        (indices items)
    in map (\i -> items[i]) is

let lines [n] (text: [n]u8) : *[](i64, i64) =
    let chunk_size = n /^ chunks
    let newline_indices =
        loop newline_indices = [] for i < chunks do
            let start = i * chunk_size
            let end = i64.min n (start + chunk_size)
            let chunk =
                filter
                    (\i -> text[i] == '\n')
                    (start ..< end)
            in newline_indices ++ chunk
    -- Add 0 for the first line and add 1 to the others to map to line starts
    -- This requires the input to not have a newline at the end
    let line_starts = shift 0 (map (+1) newline_indices)
    let line_ends = newline_indices
    in zip
        line_starts
        line_ends

let extract_users [n] (text: []u8) (username_starts: [n]i64) (username_lens: [n]i64) : *[n]Username =
    map2
        (\start len ->
            scatter
                (replicate username_max_length 0u8)
                ((username_max_length - len ..< username_max_length) :> [len]i64)
                (text[start : start + len] :> [len]u8))
        username_starts
        username_lens

let extract_authors [n] (text: []u8) (line_starts: [n]i64) : *[n](i64, i64) =
    let author_starts = line_starts |> map (+ timestamp_length + 1)
    let author_ends =
        map
            (iterate_until
                (\j -> text[j] == '\t')
                (+1))
            author_starts
    in zip
        (copy author_starts)
        (map2 (-) author_ends author_starts)

let extract_mentions [n] (text: [n]u8): *[](i64, i64) =
    let mention_starts =
        let chunk_size = n /^ chunks
        in loop mention_starts = [] for i < chunks do
            let start = i * chunk_size
            let end = i64.min n (start + chunk_size)
            let chunk = filter
                (is_mention_start text)
                (start ..< end)
            in mention_starts ++ (map (+1) chunk)
    let mention_max_index =
        map
            (\i -> i64.min (length text) (i + username_max_length))
            mention_starts
    let mention_lens =
        map2
            (\start_index max_index ->
                let end_index = iterate_while
                    (\i -> i < max_index && is_allowed_in_username text[i])
                    (+1)
                    start_index
                let delim_valid = end_index == (length text) || is_mention_delimiter text[end_index]
                -- Mentions which are invalid are set to have length 0.
                -- These cannot be removed, as the order of the mentions
                -- array has to be preserved to be able to map it to lines
                in if delim_valid then end_index - start_index else 0)
            mention_starts
            mention_max_index
    in zip mention_starts mention_lens

let extract_mention_sources [n] (text: []u8) (author_ids: [n]i64) (author_ends: [n]i64) (line_ends: [n]i64): *[]i64 =
    let mention_counts =
        map2
            (\start end ->
                (start ..< end) |> map (is_mention_start text) |> map i64.bool |> reduce (+) 0)
            author_ends
            line_ends
    let total_mentions = reduce (+) 0 mention_counts
    let nonzero_indices = filter (\i -> mention_counts[i] > 0) (indices mention_counts)
    let nonzero_author_ids = map (\i -> author_ids[i]) nonzero_indices
    let nonzero_counts = map (\i -> mention_counts[i]) nonzero_indices
    let nonzero_counts_prefix = shift 0 (scan (+) 0 nonzero_counts)
    let m = length nonzero_counts_prefix
    let start_flags =
        scatter
            (replicate total_mentions 0i64)
            (nonzero_counts_prefix :> [m]i64)
            ((replicate (length nonzero_counts_prefix) 1i64) :> [m]i64)
    let is = start_flags |> scan (+) 0 |> map (\i -> i - 1)
    in map (\i -> nonzero_author_ids[i]) is

let get_username_bit (index: i32) (username: Username): i32 =
    let byte = (i32.i64 username_max_length) - 1 - index / 8
    let bit = index % 8
    in u8.get_bit bit username[byte]

let sort_users [n] (users: *[n]Username): *[n]Username =
    sort.radix_sort
        (i32.i64 username_max_length * 8)
        get_username_bit
        users

let canonicalize_users [n] (users: [n]Username): [n]Username =
    let to_lower (c: u8): u8 =
        if c >= 'A' && c <= 'Z'
            then c + 'a' - 'A'
            else c
    in map (map to_lower) users

let sort_and_dedup_users (users: *[]Username): *[]Username =
    let sorted = sort_users users
    let unique = deduplicate username_eq sorted
    -- Filter out the invalid user (all zeros)
    -- Due to the sort, it can only appear at the very start
    in if (all (==0) unique[0])
        then unique[1:]
        else unique

let main (text: []u8) : ([]i64, []i64, []Username) =
    let (line_starts, line_ends) =
        lines text
        |> unzip
    let (author_starts, author_lens) =
        extract_authors text line_starts
        |> unzip
    let authors =
        extract_users text author_starts author_lens
    let (mention_starts, mention_lens) =
        extract_mentions text
        |> unzip
    let mentions =
        extract_users text mention_starts mention_lens
        |> canonicalize_users
    let users =
        sort_and_dedup_users (authors ++ mentions)
    let author_ids =
        map (binary_search username_lte users) authors
    let mention_src_ids =
        extract_mention_sources
            text
            author_ids
            (map2 (+) author_starts author_lens)
            line_ends
    let mention_dst_ids =
        map (binary_search username_lte users) mentions
    let n_edges = length mention_src_ids
    let (mention_src_ids_filtered, mention_dst_ids_filtered) =
        zip
            (mention_src_ids :> [n_edges]i64)
            (mention_dst_ids :> [n_edges]i64)
        |> filter (\(_, dst) -> dst != -1)
        |> unzip
    in (mention_src_ids_filtered, mention_dst_ids_filtered, users)
