# VSP — Python Vulnerability Taxonomy

Focus on these bug classes (ordered by frequency in real Python CVEs):

## 1. Unsafe Deserialization
- `pickle.loads`, `pickle.load`, `cPickle.loads` → arbitrary code execution on untrusted data
- `yaml.load(x)` without `Loader=yaml.SafeLoader` → same
- `yaml.unsafe_load`, `yaml.full_load` (behaves unsafe on some versions)
- `marshal.loads`, `shelve.open` on attacker-controlled path
- `dill`, `jsonpickle` — implicitly unsafe
- Django `pickle`-based session backends with shared cache
- Check message queues (Celery with pickle serializer, ZeroMQ)

## 2. Code Injection
- `eval(`, `exec(`, `compile(` with user data
- `ast.literal_eval` is safer but still parses complex structures
- `__import__(user_string)` → arbitrary module load
- Jinja2 `Template(user_string).render()` → Server-Side Template Injection (SSTI)
- f-strings / `.format(` where the format *string* is user-controlled (access to `{x.__class__}` exposes the object graph)
- Mako, Genshi, Chameleon templates with user templates

## 3. Command Injection
- `subprocess.run(..., shell=True)`, `subprocess.Popen(..., shell=True)`, `os.system`, `os.popen`
- `commands.getoutput` (py2 legacy)
- `shlex.split` on untrusted string is NOT a sanitizer for shell=True
- Even `shell=False` with a list can be injected if `-option=`-prefixed values go to ssh/curl/etc. (argument injection)

## 4. Path Traversal
- `open(user_path)`, `shutil.copy(user_path, ...)`, `os.remove(user_path)`
- `os.path.join(safe_base, user_input)` — if `user_input` starts with `/`, join **discards** `safe_base` (Python-specific footgun)
- Archive extraction: `tarfile.extractall`, `zipfile.extractall` → zip-slip; `tar.extract` without `filter=` (Python ≥3.12 warning)
- `send_file(user_path)` in Flask, `FileResponse` in Django

## 5. SSRF
- `requests.get(user_url)`, `urllib.request.urlopen(user_url)`, `httpx`
- Check for missing scheme allow-list, no private-IP block, no DNS-rebinding protection
- Webhook endpoints, image/URL fetchers, RSS readers
- `xml.etree.ElementTree` external entity resolution (older stdlib)

## 6. XML Issues
- `xml.etree.ElementTree` — older versions resolve entities; `defusedxml` is the mitigation
- `lxml.etree.parse` with `resolve_entities=True` (default)
- Billion Laughs DoS on any of the above

## 7. SQL Injection
- Django `.extra(where=[...])`, `.raw(query)`, `cursor.execute(query % user)` with `%s` string-format, not DB-API placeholder
- SQLAlchemy `text(query)` concat, `.filter(text(...))`
- `pyodbc` / `psycopg2` raw concat

## 8. Auth / Crypto Misuse
- `hashlib.md5`, `.sha1` used for password hashing (should be Argon2/bcrypt/scrypt)
- `secrets` vs `random` — `random` is predictable for token generation
- `jwt.decode(..., verify=False)` or algorithm confusion (`alg=none`)
- Timing attacks: `==` on tokens instead of `hmac.compare_digest`

## 9. Framework-specific
- **Django:** `mark_safe`, `safe` template filter with user data, `CSRF_EXEMPT`
- **Flask:** `send_from_directory` safeguard vs `send_file` — latter has no path sanitization
- **FastAPI/Pydantic:** custom validators that return early on certain types, URL parsing before validation
- **Celery:** pickle serializer accepting tasks from untrusted brokers

## 10. Prototype-less tricks still dangerous
- `dict.update(user_dict)` where attacker controls keys → shadow built-in attrs on some ORMs
- `**kwargs` expansion of parsed user JSON
- `format()` access to `.__globals__`, `__builtins__`
- `getattr(obj, user_attr)` without allow-list → access to `_`-prefixed internals

## Python-specific VSP reasoning

1. **Input enumeration:** Framework request objects (`request.json`, `request.form`, `request.args`, `request.headers`, `request.cookies`), command-line args, env vars, IPC (multiprocessing.Queue with pickle!), message brokers
2. **Duck typing:** type annotations do **not** enforce at runtime (unless pydantic/typeguard). User can pass a `dict` where a function expects a custom object and access `__dict__`
3. **Imports are code:** `__import__(user)` or `importlib.import_module(user)` runs module top-level code
4. **Pickle gadget chains:** `PyYAML` + `pickle` modules shipped with the interpreter give RCE gadgets for free
5. **Path handling gotchas:** `pathlib.Path("/safe") / user_input` has the same `/`-absolute-override bug as `os.path.join`
