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
    @AppStorage("flexMealsRemaining") private var flexMealsRemaining: Int = 1
    @AppStorage("lastSavedDay") private var lastSavedDay: String = ""
    @AppStorage("didRunStreakZeroMigration") private var didRunStreakZeroMigration: Bool = false
    @AppStorage("lastFlexResetWeek") private var lastFlexResetWeek: String = ""
    @AppStorage("usedFlexToday") private var usedFlexToday: Bool = false
    
    @State private var events: [LogEvent] = []
    @State private var shouldScrollToTodayLog = false
    @StateObject private var healthKitManager = HealthKitManager()

    private let calendar = Calendar.current
    private let secondaryTextColor = Color.white.opacity(0.78)

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
                            historyCard
                                .id("todayLog")
                            flexMealCard
                            healthKitCard
                            zone2PlusCard
                            weeklyRunsCard
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
                restoreFromICloudIfAvailable()
                clampFlexMealsToWeeklyLimit()
                migrateStreakAndFlexIfNeeded()
                rolloverIfNewDay()
                loadEvents()
                saveStateToICloud()
                healthKitManager.refreshTodayMetrics()
                healthKitManager.refreshRunsInPastWeek()
                healthKitManager.refreshZone2PlusMinutesInPastWeek()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    restoreFromICloudIfAvailable()
                    clampFlexMealsToWeeklyLimit()
                    rolloverIfNewDay()
                    loadEvents()
                    saveStateToICloud()
                    healthKitManager.refreshTodayMetrics()
                    healthKitManager.refreshRunsInPastWeek()
                    healthKitManager.refreshZone2PlusMinutesInPastWeek()
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.subheadline)
                    .foregroundColor(secondaryTextColor)

                Text("Steady")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
            }

            Spacer()
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

    private var mealLoggingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Log Meal", subtitle: "Quick estimate of metabolic load.")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                actionButton(title: "Low Carb", subtitle: "0 Load", emoji: "🥩🥗", color: .green) {
                    addEvent(title: "Low Carb Meal", points: 0, emoji: "🥩🥗")
                }
                actionButton(title: "Medium Carb", subtitle: "+5 Load", emoji: "🍓🫐", color: .orange) {
                    addEvent(title: "Medium Carb Meal", points: 5, emoji: "🍓🫐")
                }
                actionButton(title: "High Carb", subtitle: "+10 Load", emoji: "🍚🍕", color: .red) {
                    addEvent(title: "High Carb Meal", points: 10, emoji: "🍚🍕")
                }
            }
        }
        .cardStyle()
    }

    private var activityLoggingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Log Activity", subtitle: "Exercise reduces load.")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                actionButton(title: "Low Intensity", subtitle: "-5 Recovery", emoji: "🚶", color: .blue) {
                    addEvent(title: "Low Intensity", points: -5, emoji: "🚶")
                }
                actionButton(title: "High Intensity", subtitle: "-10 Recovery", emoji: "‍🏃‍♂️🏋️‍♂️🚴", color: .purple) {
                    addEvent(title: "High Intensity", points: -10, emoji: "‍🏃‍♂️🏋️‍♂️🚴")
                }
            }
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
                    .foregroundColor(secondaryTextColor)
            } else {
                ForEach(events.reversed()) { event in
                    SwipeToDeleteLogRow(
                        event: event,
                        pointsText: pointsText(event.points),
                        onDelete: { deleteEvent(event) }
                    )
                }
            }
        }
        .cardStyle()
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
                        .foregroundColor(secondaryTextColor)
                    Text("Resets \(nextFlexResetText).")
                        .font(.caption)
                        .foregroundColor(secondaryTextColor)
                }

                Spacer()

                HStack(spacing: 8) {
                    ForEach(0..<1, id: \.self) { index in
                        Text("\(index + 1)")
                            .font(.headline.bold())
                            .foregroundColor(index < flexMealsRemaining ? .black : secondaryTextColor)
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

    

    private var healthKitCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Apple Health")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Text(healthKitManager.isAuthorized ? "Connected to today's activity data." : "Connect steps, workouts, and active energy.")
                        .font(.subheadline)
                        .foregroundColor(secondaryTextColor)
                }

                Spacer()

                Text(healthKitManager.isAuthorized ? "✅" : "❤️")
                    .font(.title2)
            }

            if healthKitManager.isAuthorized {
                HStack(spacing: 10) {
                    healthMetricPill(
                        title: "Steps",
                        value: "\(Int(healthKitManager.todaySteps))"
                    )
                    healthMetricPill(
                        title: "Energy",
                        value: "\(Int(healthKitManager.todayActiveEnergy)) kcal"
                    )
                }
            }

            if !healthKitManager.isAuthorized {
                Button {
                    healthKitManager.requestAuthorization()
                } label: {
                    Text("Connect Apple Health")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .cardStyle()
    }



    private var zone2PlusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Zone 2+ This Week")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Text(zone2PlusSubtitle)
                        .font(.subheadline)
                        .foregroundColor(secondaryTextColor)
                }

                Spacer()

                Text("❤️‍🔥")
                    .font(.title2)
            }

            zone2TotalRow

            if healthKitManager.isAuthorized {
                if healthKitManager.isLoadingZone2Plus {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }

                VStack(spacing: 8) {
                    ForEach(zone2Rows) { day in
                        zone2DayRow(day)
                    }
                }

                if let errorMessage = healthKitManager.zone2PlusErrorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(zone2Rows) { day in
                        zone2DayRow(day)
                    }
                }

                Text("Connect Apple Health above to calculate Zone 2+ minutes from workout heart-rate samples.")
                    .font(.subheadline)
                    .foregroundColor(secondaryTextColor)
            }
        }
        .cardStyle()
    }

    private var zone2PlusSubtitle: String {
        guard healthKitManager.isAuthorized else {
            return "Workout minutes at Zone 2 or above."
        }

        let threshold = healthKitManager.zone2PlusThresholdBPM

        if threshold > 0 {
            return "Workout minutes at Zone 2 or above · threshold \(threshold)+ bpm"
        }

        return "Workout minutes at Zone 2 or above."
    }

    private var zone2TotalMinutes: Int {
        zone2Rows.reduce(0) { $0 + $1.minutes }
    }

    private var zone2TotalRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly Total")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Zone 2+ minutes")
                    .font(.caption)
                    .foregroundColor(secondaryTextColor)
            }

            Spacer()

            Text("\(zone2TotalMinutes) min")
                .font(.title3.bold())
                .foregroundColor(zone2TotalMinutes > 0 ? .green : secondaryTextColor)
        }
        .padding(14)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var zone2Rows: [Zone2DaySummary] {
        if !healthKitManager.zone2PlusByDay.isEmpty {
            return healthKitManager.zone2PlusByDay
        }

        let today = calendar.startOfDay(for: Date())
        return stride(from: 6, through: 0, by: -1).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            return Zone2DaySummary(date: date, minutes: 0)
        }
    }

    private func zone2DayRow(_ day: Zone2DaySummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.weekdayText)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(day.dateText)
                    .font(.caption)
                    .foregroundColor(secondaryTextColor)
            }

            Spacer()

            Text("\(day.minutes) min")
                .font(.headline.bold())
                .foregroundColor(day.minutes > 0 ? .green : secondaryTextColor)
        }
        .padding(12)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }


    private var weeklyRunsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Runs This Week")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Text(weeklyRunsSubtitle)
                        .font(.subheadline)
                        .foregroundColor(secondaryTextColor)
                }

                Spacer()

                Text("🏃‍♂️")
                    .font(.title2)
            }

            if healthKitManager.isAuthorized {
                if healthKitManager.isLoadingRuns {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else if healthKitManager.runsInPastWeek.isEmpty {
                    Text("No running workouts found in the past 7 days.")
                        .font(.subheadline)
                        .foregroundColor(secondaryTextColor)
                } else {
                    VStack(spacing: 10) {
                        ForEach(healthKitManager.runsInPastWeek) { run in
                            weeklyRunRow(run)
                        }
                    }
                }

                if let errorMessage = healthKitManager.runsErrorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } else {
                Text("Connect Apple Health above to see your recent runs.")
                    .font(.subheadline)
                    .foregroundColor(secondaryTextColor)
            }
        }
        .cardStyle()
    }

    private var weeklyRunsSubtitle: String {
        guard healthKitManager.isAuthorized else {
            return "Recent running workouts from Apple Health."
        }

        let count = healthKitManager.runsInPastWeek.count
        if count == 1 { return "1 run in the past 7 days." }
        return "\(count) runs in the past 7 days."
    }

    private func weeklyRunRow(_ run: RunWorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(runDateText(run.startDate))
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Text(run.durationText)
                    .font(.subheadline.bold())
                    .foregroundColor(.green)
            }

            HStack(spacing: 10) {
                healthMetricPill(title: "Distance", value: run.distanceText)
                healthMetricPill(title: "Heart Rate", value: run.heartRateRangeText)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func runDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    private func healthMetricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(secondaryTextColor)
            Text(value)
                .font(.headline.bold())
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.title3.bold())
                .foregroundColor(.white)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(secondaryTextColor)
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
                    .foregroundColor(.white.opacity(0.78))
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
        saveStateToICloud()
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
        flexMealsRemaining = max(0, min(1, 1 - remainingFlexEvents))
        usedFlexToday = remainingFlexEvents > 0
        saveEvents()
        saveStateToICloud()
    }

    private func clampFlexMealsToWeeklyLimit() {
        flexMealsRemaining = max(0, min(1, flexMealsRemaining))
    }

    private var nextFlexResetText: String {
        guard let nextWeekStart = calendar.nextDate(
            after: Date(),
            matching: DateComponents(weekday: calendar.firstWeekday),
            matchingPolicy: .nextTime,
            direction: .forward
        ) else {
            return "next week"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: nextWeekStart)
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
        flexMealsRemaining = 1
        lastFlexResetWeek = currentWeek
    }

    private func migrateStreakAndFlexIfNeeded() {
        guard !didRunStreakZeroMigration else { return }
        streak = 0
        flexMealsRemaining = 1
        lastFlexResetWeek = weekKey()
        usedFlexToday = false
        dailyLoad = 0
        events = []
        saveEvents()
        lastSavedDay = todayKey()
        didRunStreakZeroMigration = true
        saveStateToICloud()
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
        saveStateToICloud()
    }

    private func saveEvents() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: "events")
        }
    }

    private func loadEvents() {
        guard let data = UserDefaults.standard.data(forKey: "events"),
              let decoded = try? JSONDecoder().decode([LogEvent].self, from: data) else {
            return
        }
        events = decoded.filter { calendar.isDateInToday($0.date) }
    }

    private func saveStateToICloud() {
        let store = NSUbiquitousKeyValueStore.default

        store.set(true, forKey: "steady.hasSavedState")
        store.set(dailyLoad, forKey: "steady.dailyLoad")
        store.set(streak, forKey: "steady.streak")
        store.set(flexMealsRemaining, forKey: "steady.flexMealsRemaining")
        store.set(lastSavedDay, forKey: "steady.lastSavedDay")
        store.set(didRunStreakZeroMigration, forKey: "steady.didRunStreakZeroMigration")
        store.set(lastFlexResetWeek, forKey: "steady.lastFlexResetWeek")
        store.set(usedFlexToday, forKey: "steady.usedFlexToday")

        if let data = try? JSONEncoder().encode(events) {
            store.set(data, forKey: "steady.events")
        }

        store.synchronize()
    }

    private func restoreFromICloudIfAvailable() {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()

        guard store.bool(forKey: "steady.hasSavedState") else { return }

        dailyLoad = Int(store.longLong(forKey: "steady.dailyLoad"))
        streak = Int(store.longLong(forKey: "steady.streak"))
        flexMealsRemaining = max(0, min(1, Int(store.longLong(forKey: "steady.flexMealsRemaining")))
        lastSavedDay = store.string(forKey: "steady.lastSavedDay") ?? ""
        didRunStreakZeroMigration = store.bool(forKey: "steady.didRunStreakZeroMigration")
        lastFlexResetWeek = store.string(forKey: "steady.lastFlexResetWeek") ?? ""
        usedFlexToday = store.bool(forKey: "steady.usedFlexToday")

        if let data = store.data(forKey: "steady.events"),
           let decoded = try? JSONDecoder().decode([LogEvent].self, from: data) {
            events = decoded.filter { calendar.isDateInToday($0.date) }
            saveEvents()
        }
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
                    .foregroundColor(event.points > 0 ? .orange : event.points < 0 ? .green : .white.opacity(0.78))
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
