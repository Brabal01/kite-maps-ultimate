package app.kite.core

import kotlin.test.*

class SearchTests {
    private val here = LatLng(50.9097, -1.4044)
    private fun p(id: String, lat: Double, lng: Double, cat: String? = "Supermarket") =
        Place(id, id, LatLng(lat, lng), "osm").also { it.category = cat }

    @Test fun withoutGoogleNearestFirstNoStreets() {
        val far = p("oxford", 51.75, -1.25)
        val near2 = p("shirley", 50.92, -1.43)
        val near1 = p("portswood", 50.911, -1.405)
        val street = p("tesco road", 50.91, -1.40, "Street")
        val out = Photon.merge(listOf(near2, street), listOf(far, near1, near2), here, "tesco")
        assertEquals(listOf("portswood", "shirley", "oxford"), out.map { it.id })
    }

    @Test fun streetsKeptWhenAskedFor() {
        val street = p("high street", 50.91, -1.40, "Street")
        val shop = p("high street shoes", 50.92, -1.41)
        assertTrue(Photon.merge(listOf(street, shop), emptyList(), here, "high street").any { it.id == "high street" })
    }
}
