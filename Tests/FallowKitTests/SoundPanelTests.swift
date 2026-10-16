import AppKit
import Testing
@testable import FallowKit

@Suite @MainActor struct SoundPanelTests {
    func makePanel() -> (SoundPanel, WriterSettings) {
        let name = "FallowPanelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = WriterSettings(defaults: defaults)
        let panel = SoundPanel(settings: settings)
        _ = panel.view
        return (panel, settings)
    }

    func click(_ row: ChoiceRow, _ title: String) {
        row.buttons.first { $0.title == title }!.performClick(nil)
    }

    func chosen(_ row: ChoiceRow) -> [String] {
        row.buttons.filter(\.isChosen).map(\.title)
    }

    @Test func choicesAndVolumesReachSettings() {
        let (panel, settings) = makePanel()
        click(panel.ambientChoices, "Wind")
        #expect(settings.ambientChoice == .wind && settings.ambientSound)
        #expect(chosen(panel.ambientChoices) == ["Wind"])
        click(panel.ambientChoices, "Off")
        #expect(!settings.ambientSound)
        #expect(!panel.ambientSlider.isEnabled)
        click(panel.keysChoices, "Off")
        #expect(!settings.keystrokeSounds)
        #expect(chosen(panel.keysChoices) == ["Off"])

        panel.keysSlider.floatValue = 0.25
        _ = panel.keysSlider.target?.perform(panel.keysSlider.action, with: panel.keysSlider)
        #expect(settings.keystrokeVolume == 0.25)
        panel.ambientSlider.floatValue = 0.6
        _ = panel.ambientSlider.target?.perform(panel.ambientSlider.action, with: panel.ambientSlider)
        #expect(settings.ambientVolume == 0.6)
    }

    @Test func followsTheSoundMenu() {
        let (panel, settings) = makePanel()
        #expect(chosen(panel.ambientChoices) == ["Low Field"])
        #expect(chosen(panel.keysChoices) == ["Marimba"])
        #expect(panel.keysSlider.floatValue == WriterSettings.defaultKeystrokeVolume)
        settings.ambientChoice = .wind
        #expect(chosen(panel.ambientChoices) == ["Wind"])
        settings.ambientSound = false
        #expect(chosen(panel.ambientChoices) == ["Off"])
        settings.keystrokeSounds = false
        #expect(chosen(panel.keysChoices) == ["Off"])
    }

    @Test func choicesReadAsRadioButtons() {
        let (panel, _) = makePanel()
        let button = panel.ambientChoices.buttons[0]
        #expect(button.accessibilityRole() == .radioButton)
        #expect(button.accessibilityValue() as? Int == 1)
        #expect(panel.ambientChoices.buttons[1].accessibilityValue() as? Int == 0)
    }
}
