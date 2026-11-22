package app.kite.core

import kotlin.test.*

class NoRouteTests {
    private val soton = LatLng(50.9097, -1.4044)

    @Test fun tooFar() {
        assertEquals("Too far to walk.", Directions.noRouteReason(soton, LatLng(56.4, -3.4), TravelMode.WALK, null))
        assertNull(Directions.noRouteReason(soton, LatLng(51.5, -0.12), TravelMode.WALK, null))
        assertEquals("Too far to drive.", Directions.noRouteReason(soton, LatLng(38.5, -121.7), TravelMode.DRIVE, null))
    }

    @Test fun unknownWhenNothingToGoOn() {
        assertNull(Directions.noRouteReason(soton, LatLng(51.5, -0.12), TravelMode.DRIVE, null))
        assertNull(Directions.noRouteReason(soton, LatLng(51.5, -0.12), TravelMode.DRIVE, emptyList()))
    }
}
