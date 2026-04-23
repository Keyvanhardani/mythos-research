# Redirect Attack Classes
# When the primary analysis doesn't find memory corruption,
# redirect the agent to focus on these alternative vulnerability classes.

## Class 1: Command Injection
Focus on code paths where untrusted data reaches:
- system(), popen(), exec*() calls
- String formatting into shell commands
- Unsanitized function/symbol names used in tool invocations
e.g. unsanitized function/symbol names used in tool invocations

## Class 2: Integer Overflow → Heap Corruption  
Focus on arithmetic on untrusted values BEFORE they're used as sizes:
- width * height * bpp (image dimensions)
- count * element_size (array allocations)
- offset + length (bounds checks that overflow)
Especially: mixed-width arithmetic (uint16_t * uint16_t stored in uint32_t)

## Class 3: Use-After-Free
Focus on object lifecycle:
- Error paths that free but don't NULL the pointer
- Callback chains where an object might be freed mid-iteration
- Reference counting errors

## Class 4: Type Confusion
Focus on format/type dispatch:
- Header field says "type A" but code processes as "type B"
- Pixel format resolved one way, but raw bpp field used differently
- Object cast without type validation
e.g. classic image-decoder type-confusion bugs (bits-per-pixel vs pixmap-depth mismatch)

## Class 5: TOCTOU Race Conditions
Focus on check-then-use patterns:
- File stat then open
- Permission check then action
- Size check then read (with concurrent modification possible)

## Class 6: Format String
Focus on user-controlled strings reaching printf-family:
- Error messages that include untrusted data
- Logging that formats user input
- snprintf with user-controlled format string

## Class 7: Uninitialized Memory
Focus on:
- Stack variables used before assignment on error paths
- Heap allocations (malloc, not calloc) read before full initialization
- Struct padding leaked to output
