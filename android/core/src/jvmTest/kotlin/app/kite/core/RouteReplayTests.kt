package app.kite.core

import org.w3c.dom.Element
import java.time.Instant
import javax.xml.parsers.DocumentBuilderFactory
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/** Tests shared navigation geometry with OSM-routed GPX traces, independent of provider availability. */
class RouteReplayTests {
    private data class Sample(val point: LatLng, val time: Instant)

    @Test fun olomouc() = replay("olomouc", TravelMode.DRIVE)
    @Test fun prague() = replay("prague", TravelMode.WALK)
    @Test fun brno() = replay("brno", TravelMode.DRIVE)
    @Test fun valasskeMezirici() = replay("valasske-mezirici", TravelMode.DRIVE)
    @Test fun vienna() = replay("vienna", TravelMode.WALK)
    @Test fun london() = replay("london", TravelMode.DRIVE, left = true)
    @Test fun paris() = replay("paris", TravelMode.WALK)
    @Test fun amsterdam() = replay("amsterdam", TravelMode.WALK)
    @Test fun newYork() = replay("new-york", TravelMode.DRIVE)
    @Test fun tokyo() = replay("tokyo", TravelMode.DRIVE, left = true)

    private fun replay(slug: String, mode: TravelMode, left: Boolean = false) {
        val factory = DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = true
            setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
        }
        val document = assertNotNull(javaClass.getResourceAsStream("/gpx/$slug.gpx")).use {
            factory.newDocumentBuilder().parse(it)
        }
        val nodes = document.getElementsByTagNameNS("http://www.topografix.com/GPX/1/1", "trkpt")
        val samples = (0 until nodes.length).map { i ->
            val element = nodes.item(i) as Element
            val point = LatLng(element.getAttribute("lat").toDouble(), element.getAttribute("lon").toDouble())
            val time = Instant.parse(element.getElementsByTagNameNS("*", "time").item(0).textContent)
            Sample(point, time)
        }

        assertTrue(samples.size >= 10, slug)
        assertTrue(samples.zipWithNext().all { (a, b) -> b.time.isAfter(a.time) }, slug)
        val line = samples.map { it.point }
        assertEquals(left, Geo.drivesOnLeft(line.first()), slug)
        val distance = Geo.length(line)
        assertTrue(distance >= 400, slug)
        val route = Route(
            mode = mode, polyline = line, distanceMeters = distance,
            typicalSeconds = (samples.last().time.epochSecond - samples.first().time.epochSecond).toDouble(),
            trafficSeconds = null, summary = null, maneuvers = mutableListOf(), source = "gpx",
        )
        val tracker = RouteTracker(route)
        assertTrue(tracker.update(line.first()).remainingMeters > distance - 2, slug)
        var previousAlong = 0.0
        for ((index, sample) in samples.withIndex()) {
            val heading = if (index % 2 == 0) 90.0 else 270.0
            val measured = Geo.destination(sample.point, heading, 2.0)
            val progress = tracker.update(measured, accuracy = 12.0)
            assertFalse(progress.offRoute, "$slug sample $index")
            assertTrue(progress.offsetMeters < 7.0, "$slug sample $index")
            assertTrue(progress.alongMeters >= previousAlong - 20.0, "$slug sample $index")
            previousAlong = progress.alongMeters
        }
        assertTrue(tracker.update(line.last()).arrived, slug)
    }
}
