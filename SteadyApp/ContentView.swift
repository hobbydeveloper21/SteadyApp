import SwiftUI

struct LogEvent: Identifiable, Codable {
    let id: UUID
    let title: String
    let points: Int
    let emoji: String
    let date: Date
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("dailyLoad") private var dailyLoad: Int = 0
    @AppStorage("streak") private var streak: Int = 0
    @AppStorage("flexMealsRemaining") private var flexMealsRemaining: Int = 2
    @AppStorage("lastSavedDay") private var lastSavedDay: String = ""
    @AppStorage("didRunStreakZeroMigration") private var didRunStreakZeroMigration: Bool = false
    @AppStorage("lastFlexResetWeek") private var lastFlexResetWeek: String = ""
    @AppStorage("usedFlexToday") private var usedFlexToday: Bool = false
    @State private var events: [LogEvent] = []
    @State private var showResetAlert = false
    @State private var shouldScrollToTodayLog = false

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.05, green: 0.07, blue: 0.07)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 18) {
                            header
                            streakCard
                            mealLoggingCard
                            activityLoggingCard
                            coachCard
                            historyCard
                                .id("todayLog")
                            flexMealCard
                            Spacer(minLength: 80)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }
                    .onChange(of: events.count) { _ in
                        guard shouldScrollToTodayLog else { return }
                        shouldScrollToTodayLog = false
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            proxy.scrollTo("todayLog", anchor: .top)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                migrateStreakAndFlexIfNeeded()
                rolloverIfNewDay()
                loadEvents()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    rolloverIfNewDay()
                    loadEvents()
                }
            }
            .alert("Reset today?", isPresented: $showResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    dailyLoad = 0
                    if usedFlexToday && flexMealsRemaining < 2 { flexMealsRemaining += 1 }
                    usedFlexToday = false
                    events = []
                    saveEvents()
                }
            } message: {
                Text("This clears today's logged meals and activities.")
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Steady")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
            }
            Spacer()
            Button {
                showResetAlert = true
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Current Stability Streak")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.black.opacity(0.65))

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(streak)")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                Text("Stable Days")
                    .font(.title3.bold())
            }
            .foregroundColor(.black)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Load")
                        .font(.caption)
                        .foregroundColor(.black.opacity(0.6))
                    Text(pointsText(dailyLoad))
                        .font(.title.bold())
                        .foregroundColor(.black)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Status")
                        .font(.caption)
                        .foregroundColor(.black.opacity(0.6))
                    Text(statusLabel)
                        .font(.title3.bold())
                        .foregroundColor(.black)
                }
            }
            .padding(16)
            .background(Color.black.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.86, blue: 0.50), Color(red: 0.76, green: 0.95, blue: 0.32)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .green.opacity(0.25), radius: 30, y: 18)
    }

    private var flexMealCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Flex Meals")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Text("Use for celebrations or social meals.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { index in
                        Text("\(index + 1)")
                            .font(.headline.bold())
                            .foregroundColor(index < flexMealsRemaining ? .black : .secondary)
                            .frame(width: 42, height: 42)
                            .background(index < flexMealsRemaining ? Color.yellow : Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }

            Button {
                rolloverIfNewDay()
                guard flexMealsRemaining > 0 else { return }
                flexMealsRemaining -= 1
                usedFlexToday = true
                addEvent(title: "Flex Meal", points: 0, emoji: "🎉")
            } label: {
                Text(flexMealsRemaining > 0 ? "Use Flex Meal" : "No Flex Meals Left")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(flexMealsRemaining > 0 ? Color.yellow : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(flexMealsRemaining == 0)
        }
        .cardStyle()
    }

    private var mealLoggingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Log Meal", subtitle: "Quick estimate of metabolic load.")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                actionButton(title: "Low Carb", subtitle: "0 Load", emoji: "🥗", color: .green) {
                    addEvent(title: "Low Carb Meal", points: 0, emoji: "🥗")
                }
                actionButton(title: "Medium Carb", subtitle: "+5 Load", emoji: "🍛", color: .orange) {
                    addEvent(title: "Medium Carb Meal", points: 5, emoji: "🍛")
                }
                actionButton(title: "High Carb", subtitle: "+10 Load", emoji: "🍚", color: .red) {
                    addEvent(title: "High Carb Meal", points: 10, emoji: "🍚")
                }
                actionButton(title: "Photo", subtitle: "Coming soon", emoji: "📷", color: .gray) {
                    addEvent(title: "Photo Meal", points: 5, emoji: "📷")
                }
            }
        }
        .cardStyle()
    }

    private var activityLoggingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Log Activity", subtitle: "Recovery actions reduce load.")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                actionButton(title: "Walk", subtitle: "-5 Recovery", emoji: "🚶", color: .blue) {
                    addEvent(title: "Walk", points: -5, emoji: "🚶")
                }
                actionButton(title: "High Intensity Workout", subtitle: "-10 Recovery", emoji: "🏃‍♂️🏋️", color: .purple) {
                    addEvent(title: "High Intensity Workout", points: -10, emoji: "🏃‍♂️🏋️")
                }
            }
        }
        .cardStyle()
    }

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Coach")
                .font(.title3.bold())
                .foregroundColor(.white)
            Text(coachMessage)
                .font(.body)
                .foregroundColor(.white.opacity(0.82))
                .lineSpacing(4)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .cardStyle()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Today")
                .font(.title3.bold())
                .foregroundColor(.white)
            if events.isEmpty {
                Text("No meals or activities logged yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(events.reversed()) { event in
                    SwipeToDeleteLogRow(
                        event: event,
                        pointsText: pointsText(event.points),
                        onDelete: {
                            deleteEvent(event)
                        }
                    )
                }
            }
        }
        .cardStyle()
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.title3.bold())
                .foregroundColor(.white)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func actionButton(title: String, subtitle: String, emoji: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(emoji)
                    .font(.title2)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(color.opacity(0.20))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(color.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var statusLabel: String {
        if dailyLoad <= 0 { return "Stable" }
        if dailyLoad <= 5 { return "Slight Load" }
        if dailyLoad <= 15 { return "Elevated" }
        return "Recovery Needed"
    }

    private var coachMessage: String {
        if dailyLoad <= 0 {
            return "You’re balanced today. Keep the streak going with a simple, steady dinner."
        } else if dailyLoad <= 5 {
            return "A short walk tonight would likely bring you back to a Stable Day."
        } else if dailyLoad <= 15 {
            return "You’re carrying some metabolic load. A workout or longer walk can help protect the streak."
        } else {
            return "Make this a recovery evening: light dinner, walk if possible, and prioritize sleep."
        }
    }

    private var greeting: String {
        let hour = calendar.component(.hour, from: Date())
        if hour < 12 { return "Good Morning" }
        if hour < 18 { return "Good Afternoon" }
        return "Good Evening"
    }

    private func addEvent(title: String, points: Int, emoji: String) {
        rolloverIfNewDay()
        dailyLoad += points
        events.append(LogEvent(id: UUID(), title: title, points: points, emoji: emoji, date: Date()))
        saveEvents()
        shouldScrollToTodayLog = true
    }

    private func deleteEvent(_ event: LogEvent) {
        var updatedEvents = events
        updatedEvents.removeAll { $0.id == event.id }

        events = updatedEvents
        dailyLoad = updatedEvents.reduce(0) { total, event in
            total + event.points
        }

        let remainingFlexEvents = updatedEvents.filter { $0.title == "Flex Meal" }.count
        flexMealsRemaining = max(0, min(2, 2 - remainingFlexEvents))
        usedFlexToday = remainingFlexEvents > 0

        saveEvents()
    }

    private func pointsText(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }



    private func weekKey() -> String {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let year = components.yearForWeekOfYear ?? 0
        let week = components.weekOfYear ?? 0
        return "\(year)-W\(week)"
    }

    private func resetFlexMealsIfNewWeek() {
        let currentWeek = weekKey()
        guard lastFlexResetWeek != currentWeek else { return }
        flexMealsRemaining = 2
        lastFlexResetWeek = currentWeek
    }

    private func migrateStreakAndFlexIfNeeded() {
        guard !didRunStreakZeroMigration else { return }

        streak = 0
        flexMealsRemaining = 2
        lastFlexResetWeek = weekKey()
        usedFlexToday = false
        dailyLoad = 0
        events = []
        saveEvents()
        lastSavedDay = todayKey()
        didRunStreakZeroMigration = true
    }

    private func rolloverIfNewDay() {
        let today = todayKey()
        guard lastSavedDay != today else { return }

        if !lastSavedDay.isEmpty {
            if dailyLoad <= 0 {
                streak += 1
            } else if usedFlexToday {
                // Flex day: preserve streak without incrementing.
            } else {
                streak = 0
            }
        }

        dailyLoad = 0
        usedFlexToday = false
        resetFlexMealsIfNewWeek()
        events = []
        saveEvents()
        lastSavedDay = today
    }

    private func saveEvents() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: "events")
        }
    }

    private func loadEvents() {
        guard let data = UserDefaults.standard.data(forKey: "events"),
              let decoded = try? JSONDecoder().decode([LogEvent].self, from: data) else { return }
        events = decoded.filter { calendar.isDateInToday($0.date) }
    }
}


struct SwipeToDeleteLogRow: View {
    let event: LogEvent
    let pointsText: String
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isOpen = false

    private let deleteWidth: CGFloat = 92

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack {
                Spacer()
                Text("Delete")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .frame(width: deleteWidth, height: 52)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onDelete()
                    }
            }
            .zIndex(1)

            HStack {
                Text(event.emoji)
                    .font(.title2)
                Text(event.title)
                    .foregroundColor(.white)
                Spacer()
                Text(pointsText)
                    .foregroundColor(event.points > 0 ? .orange : event.points < 0 ? .green : .secondary)
                    .font(.headline)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 2)
            .background(Color(red: 0.05, green: 0.07, blue: 0.07))
            .offset(x: offset)
            .contentShape(Rectangle())
            .allowsHitTesting(!isOpen)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        let proposedOffset = value.translation.width + (isOpen ? -deleteWidth : 0)
                        offset = min(0, max(-deleteWidth, proposedOffset))
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            if value.translation.width < -36 {
                                offset = -deleteWidth
                                isOpen = true
                            } else {
                                offset = 0
                                isOpen = false
                            }
                        }
                    }
            )
            .zIndex(2)
        }
        .frame(minHeight: 52)
        .clipped()
    }
}

extension View {
    func cardStyle() -> some View {
        self
            .padding(18)
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

#Preview {
    ContentView()
}
