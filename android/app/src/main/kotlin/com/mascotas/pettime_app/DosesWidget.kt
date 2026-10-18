package com.mascotas.pettime_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.graphics.Typeface
import android.text.SpannableStringBuilder
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import org.json.JSONArray

/**
 * "Próximas tomas" on the home screen. The app saves the pending doses of the
 * next days (home_widget_service.dart); this picks the next ones by the clock,
 * so the widget stays right between the app's updates.
 */
class DosesWidget : HomeWidgetProvider() {

  private class Dose(val time: Long, val until: Long, val title: String, val detail: String)

  private val rows = listOf(
      intArrayOf(R.id.row1, R.id.row1_time, R.id.row1_text),
      intArrayOf(R.id.row2, R.id.row2_time, R.id.row2_text),
      intArrayOf(R.id.row3, R.id.row3_time, R.id.row3_text),
      intArrayOf(R.id.row4, R.id.row4_time, R.id.row4_text),
  )

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val now = System.currentTimeMillis()
    val doses = parse(widgetData.getString("doses", null)).filter { it.until > now }
    val hasPets = widgetData.getBoolean("hasPets", false)
    for (id in appWidgetIds) {
      val views = RemoteViews(context.packageName, R.layout.doses_widget)
      views.setOnClickPendingIntent(
          R.id.widget_root,
          HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
      )
      views.setViewVisibility(R.id.empty, if (doses.isEmpty()) View.VISIBLE else View.GONE)
      views.setTextViewText(
          R.id.empty,
          if (hasPets) "No hay tomas pendientes ✓" else "Abrí PetTime para cargar a tu mascota",
      )
      rows.forEachIndexed { i, ids ->
        val dose = doses.getOrNull(i)
        views.setViewVisibility(ids[0], if (dose == null) View.GONE else View.VISIBLE)
        if (dose != null) {
          val due = dose.time <= now
          val day = dayLabel(dose.time, now)
          val time = timeFormat.format(Date(dose.time))
          views.setTextViewText(ids[1], if (day.isEmpty()) time else "$day $time")
          views.setTextColor(ids[1], if (due) RED else TEAL)
          // "Pancho · Amoxicilina" in bold, then the dose in grey.
          val text = SpannableStringBuilder(dose.title)
          text.setSpan(StyleSpan(Typeface.BOLD), 0, text.length, 0)
          if (dose.detail.isNotEmpty()) {
            val start = text.length
            text.append(" · ${dose.detail}")
            text.setSpan(ForegroundColorSpan(GREY), start, text.length, 0)
          }
          views.setTextViewText(ids[2], text)
        }
      }
      val more = doses.size - rows.size
      views.setTextViewText(R.id.more, if (more > 0) "+$more más" else "")
      appWidgetManager.updateAppWidget(id, views)
    }
  }

  private fun parse(json: String?): List<Dose> {
    if (json == null) return emptyList()
    return try {
      val array = JSONArray(json)
      (0 until array.length()).map {
        val o = array.getJSONObject(it)
        Dose(o.getLong("t"), o.getLong("u"), o.getString("title"), o.optString("detail"))
      }
    } catch (e: Exception) {
      emptyList()
    }
  }

  /** Nothing for today, "Mañ" for tomorrow, otherwise the day, e.g. "mar". */
  private fun dayLabel(time: Long, now: Long): String {
    val day = Calendar.getInstance().apply { timeInMillis = time }
    val other = Calendar.getInstance().apply { timeInMillis = now }
    if (sameDay(day, other)) return ""
    other.add(Calendar.DAY_OF_YEAR, 1)
    if (sameDay(day, other)) return "Mañ"
    return dayFormat.format(Date(time)).trimEnd('.')
  }

  private fun sameDay(a: Calendar, b: Calendar) =
      a.get(Calendar.YEAR) == b.get(Calendar.YEAR) &&
          a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)

  companion object {
    private val timeFormat = SimpleDateFormat("HH:mm", Locale.getDefault())
    private val dayFormat = SimpleDateFormat("EEE", Locale("es"))
    private val RED = Color.parseColor("#E53935")
    private val TEAL = Color.parseColor("#00897B")
    private val GREY = Color.parseColor("#757575")
  }
}
