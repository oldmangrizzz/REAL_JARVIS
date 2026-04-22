# Determinism Guard — Pattern Catalog

Reference catalog of non-deterministic patterns. Each entry: what it is, why it breaks determinism, how to detect it, and the safe alternative.

---

## Critical Severity

These patterns **always** break determinism when present in logic paths.

### C1: Unseeded Random Number Generation

**Languages:** JS/TS, Python, Go, Rust

**Why it breaks determinism:** Produces different output on every run. A single unseeded call in a simulation loop can corrupt an entire replay system, invalidate snapshot tests, and make save files non-reproducible.

**Detection patterns:**
- JS/TS: `Math.random()`
- Python: `random.random()`, `random.randint()`, `random.choice()`, `random.shuffle()`, `random.sample()`, `random.uniform()`, `random.gauss()`
- Go: `rand.Intn()`, `rand.Float64()`, `rand.Int31()`, `rand.Perm()` (from `math/rand` without `rand.NewSource`)
- Rust: `rand::random()`, `rand::thread_rng()` without explicit seed

**Safe alternatives:**
- JS/TS: Use a seeded PRNG library (e.g., `seedrandom`) or implement a seeded xorshift/LCG. Store the seed in game/app state.
- Python: `rng = random.Random(seed)` then call `rng.random()`, `rng.randint()`, etc. Never use the module-level functions.
- Go: `rng := rand.New(rand.NewSource(seed))` then call `rng.Intn()`, etc. Never use the package-level functions.
- Rust: `use rand::SeedableRng; let mut rng = rand_chacha::ChaCha8Rng::seed_from_u64(seed);`

---

### C2: Cryptographic RNG in Logic Paths

**Languages:** JS/TS, Python

**Why it breaks determinism:** Cryptographic RNG is designed to be unpredictable and cannot be seeded. Using it for game logic, IDs in state, or test fixtures guarantees non-reproducibility.

**Detection patterns:**
- JS/TS: `crypto.randomBytes()`, `crypto.randomUUID()`, `crypto.getRandomValues()`
- Python: `os.urandom()`, `secrets.token_bytes()`, `secrets.randbelow()`, `uuid.uuid4()`

**Safe alternative:** Use seeded PRNG (see C1) for all logic paths. Reserve crypto RNG exclusively for security-sensitive operations (authentication tokens, encryption keys, session IDs).

---

### C3: Wall-Clock Time in Logic

**Languages:** All

**Why it breaks determinism:** Returns different values on every run. When used for IDs, timestamps in state, or branching logic, it makes outputs unreproducible. A `Date.now()` used as a "unique ID" in a save file means no two saves are comparable.

**Detection patterns:**
- JS/TS: `Date.now()`, `new Date()`, `performance.now()`
- Python: `datetime.now()`, `datetime.utcnow()`, `time.time()`, `time.monotonic()`
- Go: `time.Now()`, `time.Since()`
- Rust: `std::time::SystemTime::now()`, `std::time::Instant::now()`

**Safe alternatives:**
- Simulations/games: Use a deterministic tick counter or game clock that advances by fixed increments.
- IDs: Use a sequential counter or seeded deterministic UUID generator.
- Tests: Inject a fixed timestamp or use a clock mock/stub.
- Logging: Wall-clock time is fine in pure logging that does not affect state.

---

## High Severity

These patterns break determinism **in many contexts** but have legitimate safe uses.

### H1: Unstable Sort

**Languages:** JS/TS

**Why it breaks determinism:** `Array.sort()` without a comparator converts elements to strings and sorts lexicographically. More critically, when two elements are "equal" under the comparator, their relative order depends on the sort algorithm's stability. V8 (Node 10+, Chrome 70+) uses stable TimSort, but older engines do not guarantee stability. An incomplete comparator that returns 0 for distinct elements causes order variation.

**Detection:** `.sort()` with no arguments, or `.sort(fn)` where `fn` does not guarantee a total order (no tiebreaker for equal elements).

**Safe alternative:** Always provide an explicit, total-order comparator:
- Numbers: `.sort((a, b) => a - b)`
- Strings: `.sort((a, b) => a.localeCompare(b))`
- Objects: `.sort((a, b) => a.score - b.score || a.id.localeCompare(b.id))` — always include a unique tiebreaker field.

---

### H2: Unordered Collection Iteration

**Languages:** JS/TS, Python, Go, Rust

**Why it breaks determinism:** Iteration order is either unspecified, implementation-dependent, or intentionally randomized. Using iteration results to build ordered output (arrays, serialized state) propagates the non-determinism.

**Detection patterns:**
- JS/TS: `for...in` loops on objects, iterating `Set` or `Map` without sorting
- Python: `for x in my_set` (sets are never ordered), `for k in my_dict` (ordered since 3.7 IF construction order is deterministic)
- Go: `for k, v := range myMap` (intentionally randomized by the Go runtime)
- Rust: `for (k, v) in my_hashmap` (HashMap/HashSet use randomized hashing by default)

**Safe alternatives:**
- JS/TS: `[...mySet].sort()`, `[...myMap.entries()].sort(([a], [b]) => a.localeCompare(b))`
- Python: `for x in sorted(my_set)`, `for k in sorted(my_dict)`
- Go: Collect keys into a slice, sort, iterate the sorted slice.
- Rust: Use `BTreeMap`/`BTreeSet` instead of `HashMap`/`HashSet`, or collect into a `Vec` and sort.

---

### H3: Python hash() Randomization

**Languages:** Python

**Why it breaks determinism:** Since Python 3.3, `hash()` is randomized per process via `PYTHONHASHSEED`. Any logic that depends on hash values (custom bucketing, partitioning, caching keyed by hash) produces different results between runs.

**Detection:** `hash()` calls on strings, bytes, or custom objects in logic paths (not just as dict keys, which is fine).

**Safe alternative:** Use `hashlib` for deterministic hashing: `hashlib.sha256(s.encode()).hexdigest()`. For numeric hashes, use `int.from_bytes(hashlib.sha256(s.encode()).digest()[:8], 'big')`.

---

### H4: for...in Property Enumeration

**Languages:** JS/TS

**Why it breaks determinism:** `for...in` traverses the prototype chain. Adding or removing a property from a prototype changes the iteration set. Enumeration order across engines: integer-like keys ascending, then string keys in insertion order, then inherited properties.

**Detection:** `for (const key in obj)` or `for (let key in obj)` patterns.

**Safe alternative:** Use `Object.keys(obj)`, `Object.values(obj)`, or `Object.entries(obj)` to avoid prototype chain traversal. Sort the result if order matters for state.

---

## Medium Severity

Context-dependent patterns that break determinism only in specific situations.

### M1: Promise.race / Promise.any

**Languages:** JS/TS

**Why it breaks determinism:** The "winner" depends on timing — network latency, disk I/O speed, event loop state. If the winning result is used to set state, that state varies between runs.

**Detection:** `Promise.race()`, `Promise.any()` where the result drives state changes.

**Safe alternative:** Use `Promise.all()` and select the result deterministically (e.g., first in array order). If you need "fastest available," ensure all promises resolve to equivalent state so the winner does not matter.

---

### M2: Timer-Dependent Logic

**Languages:** JS/TS

**Why it breaks determinism:** `setTimeout` and `setInterval` timing depends on system load, event loop pressure, and timer precision. Callbacks that mutate shared state create ordering dependencies that vary between runs.

**Detection:** `setTimeout()`, `setInterval()` where the callback modifies simulation state, game state, or shared mutable data.

**Safe alternative:** Use a deterministic game loop or tick system. Separate rendering timing (variable) from simulation ticks (fixed). Advance simulation state by discrete steps, not by wall-clock elapsed time.

---

### M3: Directory Listing Order

**Languages:** JS/TS, Python, Go

**Why it breaks determinism:** Filesystem enumeration order depends on the OS, filesystem type, and sometimes inode allocation. Code that processes files in listing order produces different results on different machines.

**Detection:**
- JS/TS: `fs.readdir()`, `fs.readdirSync()`
- Python: `os.listdir()`, `pathlib.Path.iterdir()`
- Go: `os.ReadDir()`

**Safe alternative:** Always sort the listing result before processing:
- JS/TS: `const files = (await fs.readdir(dir)).sort()`
- Python: `files = sorted(os.listdir(dir))`
- Go: `entries, _ := os.ReadDir(dir); slices.SortFunc(entries, ...)`

---

### M4: Environment Variable Dependencies

**Languages:** All

**Why it breaks determinism:** Different machines, CI environments, and containers have different environment variables. Logic that branches on env vars produces machine-dependent behavior.

**Detection:**
- JS/TS: `process.env.SOMETHING`
- Python: `os.environ['KEY']`, `os.getenv('KEY')`
- Go: `os.Getenv("KEY")`

**Safe alternative:** Read environment variables once at startup, validate them, and inject as explicit typed configuration. Never read env vars deep in logic paths. For simulation code, env vars should affect configuration (number of threads, log level) but never simulation outcomes.

---

### M5: Floating-Point Comparison Without Epsilon

**Languages:** All

**Why it breaks determinism:** IEEE 754 floating-point arithmetic is not associative: `(a + b) + c` may differ from `a + (b + c)` by a ULP or more. Compiler optimizations, platform differences, and even instruction reordering can change results at the least-significant bits. Direct equality comparison fails intermittently.

**Detection:** Equality operators (`===`, `==`) used to compare computed floating-point results. Absence of epsilon/tolerance in numeric comparisons.

**Safe alternative:**
- Use epsilon comparison: `Math.abs(a - b) < EPSILON` where EPSILON is appropriate for the value range.
- For deterministic simulations, consider fixed-point arithmetic (integer math scaled by a constant, e.g., multiply by 1000 and work in integers).
- For tests, use `toBeCloseTo()` (Jest) or `pytest.approx()` instead of exact equality.
