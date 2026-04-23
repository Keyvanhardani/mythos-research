# VSP — PHP / Web Vulnerability Taxonomy

Focus on these bug classes (in rough order of historical yield in PHP audits):

## 1. Object Injection (`unserialize`)
- `unserialize($x)` **without** `['allowed_classes' => false]` or an explicit allow-list → RCE via gadget chain
- Watch for `unserialize(` on cache reads (Redis/Memcached), session data, cookies, HTTP params
- Comparison test: grep every `unserialize(` in the codebase. If one lacks the filter but the others have it, that one is the bug.

## 2. Command Injection
- `system()`, `exec()`, `shell_exec()`, `passthru()`, `popen()`, `proc_open()`, backtick operator
- Indirect: `preg_replace('/pattern/e', ...)` (deprecated but still appears), `assert($user_string)`
- Check: is the string built with concatenation from HTTP/file/DB input without `escapeshellarg`/`escapeshellcmd`?

## 3. Path Traversal / Arbitrary File Read-Write
- `file_get_contents`, `fopen`, `file_put_contents`, `include`, `require`, `readfile` with path derived from user input
- Check for missing `realpath` + prefix-check, or weak `str_replace('../', '', $x)` strips
- Watch upload endpoints: `move_uploaded_file`, `->newFile(`, `basename()` on Windows vs Linux

## 4. SSRF
- `file_get_contents($url)`, `curl_exec` with user URL, `fopen` on remote stream
- Check for missing URL-scheme allow-list, no private-range IP check, DNS rebinding window
- Dompdf-style `<img src="http://attacker/">` in user-rendered HTML

## 5. XSS / Output-Context Injection
- `echo $x`, template `{{ $x }}` (if raw), `Response->addHeader('...' . $x . '...')`
- Header injection: unencoded `"` or `\n` in Content-Disposition, Location, Set-Cookie

## 6. SQL Injection
- Raw concatenation in `->query(` / `mysqli_query(` / `PDO->exec(` — **not** prepared statements
- Dynamic table/column names (prepared statements do not protect these)
- ORDER BY and LIMIT with user input

## 7. XXE / XML
- `simplexml_load_string`, `DOMDocument::loadXML`, `SoapClient` — default libxml versions may resolve entities
- Check for `libxml_disable_entity_loader(true)` or `LIBXML_NOENT` flag usage

## 8. CSRF / State-Changing GET
- `$_GET['action']` performing writes
- Missing or weak token check on POST endpoints
- **Reference:** CVE-2025-0990

## 9. Auth / Authz Logic
- `if (isset($_SESSION['admin']))` without further check
- IDOR: resource ID from URL used in query without ownership check
- Type juggling: `==` vs `===`, `hash_equals` missing on HMAC compare

## 10. Deserialization / Format Parsing Gotchas
- `json_decode(..., true)` and then `extract()` — variable-variable injection
- `parse_str`, `extract` with user data
- `call_user_func($user_fn, ...)` where fn name is user-controlled

## PHP-specific VSP reasoning

1. **Input enumeration:** `$_GET`, `$_POST`, `$_COOKIE`, `$_SERVER['HTTP_*']`, `$_FILES`, PSR-7 `$request->getQueryParams()`, `$request->getParsedBody()`, Laravel `$request->input(`, Symfony `$request->get(`, WordPress `$_REQUEST`
2. **Cache/session read = attacker-controlled** if the cache or session backend is ever shared/exposed. Redis/Memcached are network-reachable in many deployments.
3. **Framework-specific sanitizers:** WordPress `sanitize_*` / `wp_kses_*`, Symfony `HTMLPurifier`, Laravel `{{ }}` auto-escape vs `{!! !!}`, Doctrine parameter binding
4. **Type juggling:** `"0e12345" == "0"` is true (PHP scientific notation coercion). Always check for `===`
5. **`null` byte truncation** in older PHP versions: `foo.php\x00.jpg` passed to `is_file` but `include` stops at null — still seen in some legacy code
