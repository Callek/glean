# Timing Distribution

Timing distributions are used to accumulate and store time measurement, for analyzing distributions of the timing data.

To measure the distribution of single timespans, see [Timespans](timespan.md). To record absolute times, see [Datetimes](datetime.md).

Timing distributions are recorded in a histogram where the buckets have an exponential distribution, specifically with 8 buckets for every power of 2.
That is, the function from a value \\( x \\) to a bucket index is:

\\[ \lfloor 8 \log_2(x) \rfloor \\]

This makes them suitable for measuring timings on a number of time scales without any configuration.

Timings always span the full length between `start` and `stopAndAccumulate`.
If the Glean upload is disabled when calling `start`, the timer is still started.
If the Glean upload is disabled at the time `stopAndAccumulate` is called, nothing is recorded.

Multiple concurrent timespans in different threads may be measured at the same time.

Timings are always stored and sent in the payload as nanoseconds. However, the `time_unit` parameter
controls the minimum and maximum values that will recorded:

  - `nanosecond`: 1ns <= x <= 10 minutes
  - `microsecond`: 1μs <= x <= ~6.94 days
  - `millisecond`: 1ms <= x <= ~19 years

Overflowing this range is considered an error and is reported through the error reporting mechanism. Underflowing this range is not an error and the value is silently truncated to the minimum value.

Additionally, when a metric comes from GeckoView (the `geckoview_datapoint` parameter is present), the `time_unit` parameter specifies the unit that the samples are in when passed to Glean. Glean will convert all of the incoming samples to nanoseconds internally.

## Configuration

If you wanted to create a timing distribution to measure page load times, first you need to add an entry for it to the `metrics.yaml` file:

```YAML
pages:
  page_load:
    type: timing_distribution
    description: >
      Counts how long each page takes to load
    ...
```

## API

Now you can use the timing distribution from the application's code.
Starting a timer returns a timer ID that needs to be used to stop or cancel the timer at a later point.
Multiple intervals can be measured concurrently.
For example, to measure page load time on a number of tabs that are loading at the same time, each tab object needs to store the running timer ID.

{{#include ../../tab_header.md}}

<div data-lang="Kotlin" class="tab">

```Kotlin
import mozilla.components.service.glean.GleanTimerId
import org.mozilla.yourApplication.GleanMetrics.Pages

val timerId : GleanTimerId

fun onPageStart(e: Event) {
    timerId = Pages.pageLoad.start()
}

fun onPageLoaded(e: Event) {
    Pages.pageLoad.stopAndAccumulate(timerId)
}
```

There are test APIs available too.  For convenience, properties `sum` and `count` are exposed to facilitate validating that data was recorded correctly.

Continuing the `pageLoad` example above, at this point the metric should have a `sum == 11` and a `count == 2`:

```Kotlin
import org.mozilla.yourApplication.GleanMetrics.Pages

// Was anything recorded?
assertTrue(pages.pageLoad.testHasValue())

// Get snapshot.
val snapshot = pages.pageLoad.testGetValue()

// Does the sum have the expected value?
assertEquals(11, snapshot.sum)

// Usually you don't know the exact timing values, but how many should have been recorded.
assertEquals(2L, snapshot.count)

// Was an error recorded?
assertEquals(1, pages.pageLoad.testGetNumRecordedErrors(ErrorType.InvalidValue))
```

</div>

<div data-lang="Java" class="tab">

```Java
import mozilla.components.service.glean.GleanTimerId;
import org.mozilla.yourApplication.GleanMetrics.Pages;

GleanTimerId timerId;

void onPageStart(Event e) {
    timerId = Pages.INSTANCE.pageLoad.start();
}

void onPageLoaded(Event e) {
    Pages.INSTANCE.pageLoad.stopAndAccumulate(timerId);
}
```

There are test APIs available too.  For convenience, properties `sum` and `count` are exposed to facilitate validating that data was recorded correctly.

Continuing the `pageLoad` example above, at this point the metric should have a `sum == 11` and a `count == 2`:

```Java
import org.mozilla.yourApplication.GleanMetrics.Pages;

// Was anything recorded?
assertTrue(pages.INSTANCE.pageLoad.testHasValue());

// Get snapshot.
DistributionData snapshot = pages.INSTANCE.pageLoad.testGetValue();

// Does the sum have the expected value?
assertEquals(11, snapshot.getSum);

// Usually you don't know the exact timing values, but how many should have been recorded.
assertEquals(2L, snapshot.getCount);

// Was an error recorded?
assertEquals(
    1,
    pages.INSTANCE.pageLoad.testGetNumRecordedErrors(
        ErrorType.InvalidValue
    )
);
```

</div>


<div data-lang="Swift" class="tab">

```Swift
import Glean

var timerId : GleanTimerId

func onPageStart() {
    timerId = Pages.pageLoad.start()
}

func onPageLoaded() {
    Pages.pageLoad.stopAndAccumulate(timerId)
}
```

There are test APIs available too.  For convenience, properties `sum` and `count` are exposed to facilitate validating that data was recorded correctly.

Continuing the `pageLoad` example above, at this point the metric should have a `sum == 11` and a `count == 2`:

```Swift
@testable import Glean

// Was anything recorded?
XCTAssert(pages.pageLoad.testHasValue())

// Get snapshot.
let snapshot = try! pages.pageLoad.testGetValue()

// Does the sum have the expected value?
XCTAssertEqual(11, snapshot.sum)

// Usually you don't know the exact timing values, but how many should have been recorded.
XCTAssertEqual(2, snapshot.count)

// Was an error recorded?
XCTAssertEqual(1, pages.pageLoad.testGetNumRecordedErrors(.invalidValue))
```

</div>

<div data-lang="Python" class="tab">

```Python
from glean import load_metrics
metrics = load_metrics("metrics.yaml")

class PageHandler:
    def __init__(self):
        self.timer_id = None

    def on_page_start(self, event):
        # ...
        self.timer_id = metrics.pages.page_load.start()

    def on_page_loaded(self, event):
        # ...
        metrics.pages.page_load.stop_and_accumulate(self.timer_id)
```

There are test APIs available too.  For convenience, properties `sum` and `count` are exposed to facilitate validating that data was recorded correctly.

Continuing the `page_load` example above, at this point the metric should have a `sum == 11` and a `count == 2`:

```Python
# Was anything recorded?
assert metrics.pages.page_load.test_has_value()

# Get snapshot.
snapshot = metrics.pages.page_load.test_get_value()

# Does the sum have the expected value?
assert 11 == snapshot.sum

# Usually you don't know the exact timing values, but how many should have been recorded.
assert 2 == snapshot.count

# Was an error recorded?
assert 1 == metrics.pages.page_load.test_get_num_recorded_errors(
    ErrorType.INVALID_VALUE
)
```

</div>

<div data-lang="C#" class="tab">

TODO. To be implemented in [bug 1648443](https://bugzilla.mozilla.org/show_bug.cgi?id=1648443).

</div>

{{#include ../../tab_footer.md}}

## Limits

* Timings are recorded in nanoseconds.

  * On Android, the [`SystemClock.elapsedRealtimeNanos()`](https://developer.android.com/reference/android/os/SystemClock.html#elapsedRealtimeNanos()) function is used, so it is limited by the accuracy and performance of that timer. The time measurement includes time spent in sleep.

  * On iOS, the [`mach_absolute_time`](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/KernelProgramming/services/services.html) function is used,
    so it is limited by the accuracy and performance of that timer.
    The time measurement does not include time spent in sleep.

  * On Python 3.7 and later, [`time.monotonic_ns()`](https://docs.python.org/3/library/time.html#time.monotonic_ns) is used.  On earlier versions of Python, [`time.monotonics()`](https://docs.python.org/3/library/time.html#time.monotonic) is used, which is not guaranteed to have nanosecond resolution.

* The maximum timing value that will be recorded depends on the `time_unit` parameter:

  - `nanosecond`: 1ns <= x <= 10 minutes
  - `microsecond`: 1μs <= x <= ~6.94 days
  - `millisecond`: 1ms <= x <= ~19 years

  Longer times will be truncated to the maximum value and an error will be recorded.

## Examples

* How long does it take a page to load?

## Recorded errors

* `invalid_value`: If recording a negative timespan.
* `invalid_state`: If a non-existing/stopped timer is stopped again.
* `invalid_overflow`: If recording a time longer than the maximum for the given unit.

## Reference

* [Kotlin API docs](../../../javadoc/glean/mozilla.telemetry.glean.private/-timing-distribution-metric-type/index.html)
* [Swift API docs](../../../swift/Classes/TimingDistributionMetricType.html)
* [Python API docs](../../../python/glean/metrics/timing_distribution.html)
