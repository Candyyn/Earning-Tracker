import SwiftData
import SwiftUI

struct ShiftEditorSheet: View {
    @Bindable var editor: ShiftEditorViewModel
    let allShifts: [Shift]

    var body: some View {
        NavigationStack {
            Form {
                Section("Schema") {
                    DatePicker("Börjar", selection: $editor.start, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Slutar", selection: $editor.end, displayedComponents: [.date, .hourAndMinute])
                    Menu {
                        Button("Dag · 08:00-17:00") {
                            editor.applyPreset(startHour: 8, endHour: 17, breakStartHour: 12, breakEndHour: 13)
                        }
                        Button("Kväll · 16:00-23:00") {
                            editor.applyPreset(startHour: 16, endHour: 23, breakStartHour: nil, breakEndHour: nil)
                        }
                        Button("Natt · 22:00-07:00") {
                            editor.applyPreset(startHour: 22, endHour: 7, breakStartHour: nil, breakEndHour: nil)
                        }
                    } label: {
                        Label("Använd standardpass", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    }
                }

                Section {
                    Toggle("Inkludera rast", isOn: $editor.includeBreak.animation())
                    if editor.includeBreak {
                        DatePicker("Börjar", selection: $editor.breakStart, displayedComponents: [.hourAndMinute])
                        DatePicker("Slutar", selection: $editor.breakEnd, displayedComponents: [.hourAndMinute])
                        Toggle("Betald rast", isOn: $editor.breakPaid)
                    }
                } header: {
                    Text("Rast")
                } footer: {
                    Text(editor.breakPaid ? "Betald rast räknas som arbetstid." : "Obetald rast dras av från arbetstiden.")
                }

                if let validationMessage = editor.validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                            .accessibilityLabel("Fel: \(validationMessage)")
                    }
                }
            }
            .navigationTitle(editor.isEditing ? "Redigera pass" : "Nytt pass")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { editor.requestDismissal() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editor.isEditing ? "Spara" : "Lägg till") { editor.save(allShifts: allShifts) }
                        .disabled(!editor.isValid)
                        .accessibilityIdentifier("shiftEditor.save")
                }
            }
            .confirmationDialog("Kassera ändringar?", isPresented: $editor.isDiscardConfirmationPresented, titleVisibility: .visible) {
                Button("Kassera ändringar", role: .destructive) { editor.discardChanges() }
                Button("Fortsätt redigera", role: .cancel) {}
            } message: {
                Text("Osparade ändringar går förlorade.")
            }
        }
    }
}
