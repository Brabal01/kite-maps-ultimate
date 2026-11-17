package app.kite.core

import kotlin.test.*

class NavZoomTests {
    private val mph30 = 13.4
    private val mph70 = 31.3

    @Test fun normalBetweenTurns() {
        val v = NavZoom.view(mph30, 500.0, ManeuverType.TURN_LEFT, true)
        assertEquals(702.0, v.across, 1.0)
        assertEquals(50.0, v.pitch)
    }
    @Test fun pullsBackOnLongStretch() {
        val v = NavZoom.view(mph70, 5000.0, ManeuverType.RAMP_LEFT, true)
        assertEquals(1549.0, v.across, 1.0)
        assertEquals(55.0, v.pitch)
    }
    @Test fun zoomsInBeforeTurn() {
        val far = NavZoom.view(mph30, 300.0, ManeuverType.TURN_LEFT, true)
        val mid = NavZoom.view(mph30, 180.0, ManeuverType.TURN_LEFT, true)
        val close = NavZoom.view(mph30, 50.0, ManeuverType.TURN_LEFT, true)
        assertTrue(far.across > mid.across && mid.across > close.across)
        assertEquals(330.0, close.across, 0.1)
        assertEquals(35.0, close.pitch)
    }
    @Test fun motorwayExitStaysFurtherOut() {
        val v = NavZoom.view(mph70, 50.0, ManeuverType.RAMP_LEFT, true)
        assertEquals(mph70 * 14, v.across, 0.1)
    }
    @Test fun noCloseInForStraightOrArrive() {
        assertEquals(50.0, NavZoom.view(mph30, 100.0, ManeuverType.STRAIGHT, true).pitch)
        assertEquals(50.0, NavZoom.view(mph30, 100.0, ManeuverType.ARRIVE, true).pitch)
    }
    @Test fun roundaboutStaysClose() {
        assertEquals(330.0, NavZoom.view(mph30, 50.0, ManeuverType.ROUNDABOUT, true).across, 0.1)
        assertTrue(NavZoom.view(mph30, 340.0, ManeuverType.ROUNDABOUT, true).across <= 380.0)
    }
    @Test fun walking() {
        assertEquals(NavZoom.View(300.0, 50.0), NavZoom.view(1.4, 50.0, ManeuverType.TURN_LEFT, false))
    }
}
