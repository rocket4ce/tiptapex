// A three-function test harness. The JS in this package has no build step and
// no test framework; these checks exist to pin down the parts a browser is not
// needed to prove — page normalisation (which must agree with `Tiptapex.Page`),
// the pagination maths, and the Tiptap wiring under jsdom.
//
//   mix js.test
const results = []
const pending = []

export function test(suite, name, fn) {
  const result = { suite, name, ok: true }
  results.push(result)

  const fail = (error) => {
    result.ok = false
    result.error = error
  }

  try {
    const returned = fn()
    // Async checks are collected so report() can await them; without this a
    // rejected promise would surface as an unhandled rejection and the run
    // would pass.
    if (returned && typeof returned.then === "function") {
      pending.push(returned.then(() => {}, fail))
    }
  } catch (error) {
    fail(error)
  }
}

export async function report() {
  await Promise.all(pending)

  let failed = 0
  let suite = null

  for (const result of results) {
    if (result.suite !== suite) {
      suite = result.suite
      console.log(`\n${suite}`)
    }

    if (result.ok) {
      console.log(`  ok   ${result.name}`)
    } else {
      failed += 1
      console.log(`  FAIL ${result.name}`)
      console.log(`       ${String(result.error?.message).split("\n").join("\n       ")}`)
    }
  }

  console.log(`\n${results.length} checks, ${failed} failures`)
  if (failed > 0) process.exit(1)
}
