package app.kite.core

import kotlin.test.*

class MatcherTests {
    @Test fun tolls() {
        val json = """{"edges":[{"names":["A5"],"length":1.2,"toll":false},{"names":["M6 Toll"],"length":0.4,"toll":true},{"names":["M6 Toll"],"length":3.0,"toll":true},{"names":["A38"],"length":2.0},{"length":0.02,"toll":true},{"names":["A38"],"length":1.0}]}"""
        // The M6 Toll once; 20 m of toll mark at a junction is nothing.
        assertEquals(listOf("M6 Toll"), Valhalla.parseTolls(json.toByteArray()))
        assertEquals(listOf("A toll road"), Valhalla.parseTolls("""{"edges":[{"length":0.3,"toll":true}]}""".toByteArray()))
        assertEquals(emptyList(), Valhalla.parseTolls("""{"edges":[{"names":["A33"],"length":2.0}]}""".toByteArray()))
    }

    @Test fun here() {
        val json = """{"edges":[{"names":["High Street"],"speed_limit":48},{"names":["A33","Bassett Avenue"],"speed_limit":30}]}"""
        val h = Valhalla.parseHere(json.toByteArray(), LatLng(50.93, -1.40))!!
        assertEquals("Bassett Avenue", h.road)
        assertEquals("A33", h.ref)
        // "30" with no unit in Britain is 30 mph.
        assertEquals(30 * 1.609344, h.kmh!!, 0.01)
        assertEquals("A3(M)", Valhalla.parseHere("""{"edges":[{"names":["A3(M)"]}]}""".toByteArray(), LatLng(50.9, -1.0))!!.ref)
        assertNull(Valhalla.parseHere("""{"edges":[]}""".toByteArray(), LatLng(50.9, -1.0)))
    }

    @Test fun cruiseCameras() {
        val here = LatLng(50.9000, -1.4000)
        // Driving north at 30 mph (13.4 m/s): warn from 250 m.
        val ahead = RoadCamera(1, RoadCamera.Kind.SPEED, LatLng(50.9020, -1.4000))       // 222 m straight on
        val far = RoadCamera(2, RoadCamera.Kind.SPEED, LatLng(50.9060, -1.4000))         // 667 m: not yet
        val side = RoadCamera(3, RoadCamera.Kind.SPEED, LatLng(50.9015, -1.3985))        // a road off to the right
        val behind = RoadCamera(4, RoadCamera.Kind.SPEED, LatLng(50.8985, -1.4000))
        val otherWay = RoadCamera(5, RoadCamera.Kind.SPEED, LatLng(50.9010, -1.4000), directions = listOf(180.0))
        val plate = RoadCamera(6, RoadCamera.Kind.PLATE, LatLng(50.9005, -1.4000))
        val found = CruiseCameras.ahead(listOf(far, side, behind, otherWay, plate, ahead), here, 0.0, 13.4)
        assertEquals(1L, found?.first?.id)
        assertEquals(222.0, found!!.second, 3.0)
        // On a motorway (31 m/s) the far one is in reach too, but the nearer one still comes first.
        assertEquals(1L, CruiseCameras.ahead(listOf(far, ahead), here, 0.0, 31.0)?.first?.id)
        assertNull(CruiseCameras.ahead(listOf(far, side, behind, otherWay, plate), here, 0.0, 13.4))
    }
}
