package app.kite

// What each phone does its own way, behind one shape the shared app uses. The Android versions are
// in androidMain, the iPhone ones in iosMain; everything else in Kite is the same code on both.

/** Small saved values (settings), in SharedPreferences on Android and UserDefaults on iPhone. */
expect class PrefStore(name: String) {
    fun contains(key: String): Boolean
    fun getString(key: String): String?
    fun getBoolean(key: String, def: Boolean): Boolean
    fun getInt(key: String, def: Int): Int
    fun getStringSet(key: String): Set<String>?
    fun putString(key: String, value: String?)
    fun putBoolean(key: String, value: Boolean)
    fun putInt(key: String, value: Int)
    fun putStringSet(key: String, value: Set<String>)
    fun remove(key: String)
}

/** Milliseconds from the phone's running timer (not its clock): for how old something is. */
expect fun elapsedRealtime(): Long

/** A folder for files Kite can rebuild (cached roads, cameras...). */
expect fun cacheDir(): String

/** A line in the phone's log (logcat on Android, the console on iPhone). */
expect fun klog(tag: String, message: String)

/** The phone's country, like "GB". */
expect fun systemCountry(): String

/** Which phone this is. */
expect val isIos: Boolean

/** A short buzz: a tick for a tap on the map, or a longer one for a long press. */
expect fun haptic(long: Boolean = false)

/** The screen stays on while driving. */
expect fun keepScreenOn(on: Boolean)
