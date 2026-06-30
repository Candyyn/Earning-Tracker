package studio.magnusson.livetracker

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.performClick
import org.junit.Rule
import org.junit.Test

class MainActivityTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun dashboardNavigatesToShiftsAndOpensNativeEditor() {
        awaitDashboard()
        compose.onNodeWithTag("dashboard.shifts").performClick()
        compose.onNodeWithText(compose.activity.getString(R.string.shifts)).assertIsDisplayed()
        compose.onNodeWithTag("shifts.add").performClick()
        compose.onNodeWithText(compose.activity.getString(R.string.new_shift)).assertIsDisplayed()
        compose.onNodeWithText(compose.activity.getString(R.string.day)).assertIsDisplayed()
    }

    @Test fun dashboardNavigatesToSettings() {
        awaitDashboard()
        compose.onNodeWithTag("dashboard.settings").performClick()
        compose.onNodeWithText(compose.activity.getString(R.string.pay_periods)).assertIsDisplayed()
        compose.onNodeWithText(compose.activity.getString(R.string.calendar)).assertIsDisplayed()
    }

    @Test fun presetsConfigureBreakAndDirtyDismissRequiresConfirmation() {
        awaitDashboard()
        compose.onNodeWithTag("dashboard.shifts").performClick()
        compose.onNodeWithTag("shifts.add").performClick()
        compose.onNodeWithTag("editor.preset.day").performClick()
        compose.onNodeWithTag("editor.includeBreak").assertIsOn()
        compose.onNodeWithTag("editor.preset.night").performClick()
        compose.onNodeWithTag("editor.includeBreak").assertIsOff()
        compose.onNodeWithText(compose.activity.getString(R.string.cancel)).performClick()
        compose.onNodeWithText(compose.activity.getString(R.string.discard_changes)).assertIsDisplayed()
    }

    @Test fun settingsOpensTaxRefundForecast() {
        awaitDashboard()
        compose.onNodeWithTag("dashboard.settings").performClick()
        compose.onNodeWithText(compose.activity.getString(R.string.tax_refund)).performClick()
        compose.onNodeWithText(compose.activity.getString(R.string.tax_refund)).assertIsDisplayed()
        compose.onNodeWithText(compose.activity.getString(R.string.income_year_value, java.time.LocalDate.now().year - 1)).assertIsDisplayed()
    }

    @Test fun editorDraftSurvivesActivityRecreation() {
        awaitDashboard()
        compose.onNodeWithTag("dashboard.shifts").performClick()
        compose.onNodeWithTag("shifts.add").performClick()
        compose.onNodeWithTag("editor.preset.day").performClick()
        compose.activityRule.scenario.recreate()
        compose.waitForIdle()
        compose.onNodeWithTag("editor.includeBreak").assertIsOn()
        compose.onNodeWithText(compose.activity.getString(R.string.new_shift)).assertIsDisplayed()
    }

    @Test fun earningsVisibilityPersistsAcrossNavigation() {
        awaitDashboard()
        compose.onNodeWithTag("dashboard.settings").performClick()
        compose.onNodeWithTag("settings.showEarnings").assertIsOn().performClick()
        compose.onNodeWithTag("settings.close").performClick()
        compose.onNodeWithTag("dashboard.earnings").assertTextEquals("••••••")
        compose.onNodeWithTag("dashboard.settings").performClick()
        compose.onNodeWithTag("settings.showEarnings").assertIsOff().performClick()
    }

    private fun awaitDashboard() {
        compose.waitUntil(10_000) { compose.onAllNodesWithTag("dashboard.shifts").fetchSemanticsNodes().isNotEmpty() }
    }
}
