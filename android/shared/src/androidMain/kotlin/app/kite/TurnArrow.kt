package app.kite

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import app.kite.core.ManeuverType
import kotlin.math.cos
import kotlin.math.sin

/**
 * The next turn's arrow, drawn for the Android notification (it can't use the app's own icons):
 * a white arrow on a teal circle, bending the way the turn goes.
 */
object TurnArrow {
    private fun angle(t: ManeuverType): Float? = when (t) {
        ManeuverType.TURN_LEFT -> -90f
        ManeuverType.TURN_RIGHT -> 90f
        ManeuverType.SLIGHT_LEFT, ManeuverType.KEEP_LEFT, ManeuverType.RAMP_LEFT, ManeuverType.FORK_LEFT -> -40f
        ManeuverType.SLIGHT_RIGHT, ManeuverType.KEEP_RIGHT, ManeuverType.RAMP_RIGHT, ManeuverType.FORK_RIGHT -> 40f
        ManeuverType.SHARP_LEFT -> -135f
        ManeuverType.SHARP_RIGHT -> 135f
        ManeuverType.ROUNDABOUT, ManeuverType.ARRIVE, ManeuverType.UTURN -> null
        else -> 0f
    }

    fun bitmap(t: ManeuverType, size: Int): Bitmap {
        val s = size.toFloat()
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.drawCircle(s / 2, s / 2, s / 2, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF0F766E.toInt() })
        val line = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE; style = Paint.Style.STROKE; strokeWidth = s * 0.11f
            strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
        }
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; style = Paint.Style.FILL }
        fun head(x: Float, y: Float, deg: Float) {
            // A triangle pointing along [deg] (0 = up, clockwise), its tip at (x, y).
            val r = Math.toRadians(deg.toDouble())
            val dx = sin(r).toFloat(); val dy = -cos(r).toFloat()
            val len = s * 0.2f; val half = s * 0.14f
            val bx = x - dx * len; val by = y - dy * len
            c.drawPath(Path().apply {
                moveTo(x, y); lineTo(bx - dy * half, by + dx * half); lineTo(bx + dy * half, by - dx * half); close()
            }, fill)
        }
        when (t) {
            ManeuverType.ARRIVE -> {
                // A pin.
                c.drawCircle(s / 2, s * 0.42f, s * 0.17f, line)
                c.drawLine(s / 2, s * 0.59f, s / 2, s * 0.78f, line)
            }
            ManeuverType.UTURN -> {
                val p = Path().apply {
                    moveTo(s * 0.62f, s * 0.78f); lineTo(s * 0.62f, s * 0.42f)
                    arcTo(s * 0.34f, s * 0.24f, s * 0.62f, s * 0.6f, 0f, -180f, false); lineTo(s * 0.34f, s * 0.62f)
                }
                c.drawPath(p, line); head(s * 0.34f, s * 0.78f, 180f)
            }
            ManeuverType.ROUNDABOUT -> {
                c.drawCircle(s / 2, s * 0.48f, s * 0.15f, line)
                c.drawLine(s / 2, s * 0.8f, s / 2, s * 0.63f, line)
                c.drawLine(s / 2, s * 0.33f, s / 2, s * 0.24f, line)
                head(s / 2, s * 0.14f, 0f)
            }
            else -> {
                val a = angle(t) ?: 0f
                val bendX = s / 2; val bendY = s * 0.52f
                val r = Math.toRadians(a.toDouble())
                val reach = s * 0.24f
                val endX = bendX + sin(r).toFloat() * reach; val endY = bendY - cos(r).toFloat() * reach
                c.drawPath(Path().apply { moveTo(s / 2, s * 0.82f); lineTo(bendX, bendY); lineTo(endX, endY) }, line)
                val tipX = bendX + sin(r).toFloat() * (reach + s * 0.12f); val tipY = bendY - cos(r).toFloat() * (reach + s * 0.12f)
                head(tipX, tipY, a)
            }
        }
        return bmp
    }
}
