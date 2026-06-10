//
//  HealthKitManager.swift
//  SteadyApp
//
//  Created by ASHOK KUPPUSAMY on 6/1/26.
//

import Foundation
import HealthKit
import Combine

struct RunWorkoutSummary: Identifiable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let distanceMiles: Double?
    let minimumHeartRate: Double?
    let maximumHeartRate: Double?

    var durationText: String {
        let totalMinutes = Int(duration.rounded() / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

    var distanceText: String {
        guard let distanceMiles else { return "—" }
        return String(format: "%.2f mi", distanceMiles)
    }

    var heartRateRangeText: String {
        guard let minimumHeartRate, let maximumHeartRate else { return "—" }
        return "\(Int(minimumHeartRate.rounded()))–\(Int(maximumHeartRate.rounded())) bpm"
    }
}

struct Zone2DaySummary: Identifiable {
    let id = UUID()
    let date: Date
    let minutes: Int

    var weekdayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

final class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    private let calendar = Calendar.current

    @Published var isAuthorized = false
    @Published var todaySteps: Double = 0
    @Published var todayActiveEnergy: Double = 0
    @Published var runsInPastWeek: [RunWorkoutSummary] = []
    @Published var isLoadingRuns = false
    @Published var runsErrorMessage: String?
    @Published var zone2PlusByDay: [Zone2DaySummary] = []
    @Published var isLoadingZone2Plus = false
    @Published var zone2PlusErrorMessage: String?
    @Published var zone2PlusThresholdBPM: Int = 0

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("Health data is not available on this device.")
            return
        }

        let readTypes = healthTypesToRead()

        healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("HealthKit authorization error: \(error.localizedDescription)")
                    self.isAuthorized = false
                    return
                }

                self.isAuthorized = success
                self.refreshTodayMetrics()
                self.refreshRunsInPastWeek()
                self.refreshZone2PlusMinutesInPastWeek()
            }
        }
    }

    func refreshTodayMetrics() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        guard
            let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount),
            let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        else {
            return
        }

        fetchTodaySum(for: stepType, unit: .count()) { value in
            DispatchQueue.main.async {
                self.todaySteps = value
            }
        }

        fetchTodaySum(for: energyType, unit: .kilocalorie()) { value in
            DispatchQueue.main.async {
                self.todayActiveEnergy = value
            }
        }
    }

    func refreshRunsInPastWeek() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        DispatchQueue.main.async {
            self.isLoadingRuns = true
            self.runsErrorMessage = nil
        }

        let workoutType = HKObjectType.workoutType()
        let now = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now

        let datePredicate = HKQuery.predicateForSamples(
            withStart: weekAgo,
            end: now,
            options: .strictStartDate
        )

        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, runningPredicate])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: workoutType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { [weak self] _, samples, error in
            guard let self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.runsInPastWeek = []
                    self.isLoadingRuns = false
                    self.runsErrorMessage = "Could not load runs: \(error.localizedDescription)"
                }
                return
            }

            let workouts = samples as? [HKWorkout] ?? []
            self.buildRunSummaries(from: workouts)
        }

        healthStore.execute(query)
    }

    func refreshZone2PlusMinutesInPastWeek() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        DispatchQueue.main.async {
            self.isLoadingZone2Plus = true
            self.zone2PlusErrorMessage = nil
        }

        let threshold = estimatedZone2LowerBoundBPM()
        DispatchQueue.main.async {
            self.zone2PlusThresholdBPM = threshold
        }

        let workoutType = HKObjectType.workoutType()
        let now = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now

        let datePredicate = HKQuery.predicateForSamples(
            withStart: weekAgo,
            end: now,
            options: .strictStartDate
        )
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForWorkouts(with: .cycling),
            HKQuery.predicateForWorkouts(with: .traditionalStrengthTraining),
            HKQuery.predicateForWorkouts(with: .functionalStrengthTraining),
            HKQuery.predicateForWorkouts(with: .highIntensityIntervalTraining),
            HKQuery.predicateForWorkouts(with: .walking),
            HKQuery.predicateForWorkouts(with: .elliptical),
            HKQuery.predicateForWorkouts(with: .rowing),
            HKQuery.predicateForWorkouts(with: .stairClimbing),
            HKQuery.predicateForWorkouts(with: .other)
        ])
        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, predicate])

        let query = HKSampleQuery(
            sampleType: workoutType,
            predicate: compoundPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { [weak self] _, samples, error in
            guard let self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.zone2PlusByDay = self.emptyZone2SummariesEndingToday()
                    self.isLoadingZone2Plus = false
                    self.zone2PlusErrorMessage = "Could not load Zone 2+ minutes: \(error.localizedDescription)"
                }
                return
            }

            let workouts = samples as? [HKWorkout] ?? []
            self.buildZone2PlusSummaries(from: workouts, thresholdBPM: threshold)
        }

        healthStore.execute(query)
    }

    private func healthTypesToRead() -> Set<HKObjectType> {
        var readTypes = Set<HKObjectType>()

        if let stepCount = HKObjectType.quantityType(forIdentifier: .stepCount) {
            readTypes.insert(stepCount)
        }

        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            readTypes.insert(activeEnergy)
        }

        if let exerciseTime = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) {
            readTypes.insert(exerciseTime)
        }

        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            readTypes.insert(heartRate)
        }

        if let restingHeartRate = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
            readTypes.insert(restingHeartRate)
        }

        if let dateOfBirth = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            readTypes.insert(dateOfBirth)
        }

        readTypes.insert(HKObjectType.workoutType())

        return readTypes
    }

    private func fetchTodaySum(
        for quantityType: HKQuantityType,
        unit: HKUnit,
        completion: @escaping (Double) -> Void
    ) {
        let startOfDay = calendar.startOfDay(for: Date())

        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: Date(),
            options: .strictStartDate
        )

        let query = HKStatisticsQuery(
            quantityType: quantityType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, result, error in
            if let error = error {
                print("HealthKit query error: \(error.localizedDescription)")
                completion(0)
                return
            }

            let value = result?.sumQuantity()?.doubleValue(for: unit) ?? 0
            completion(value)
        }

        healthStore.execute(query)
    }

    private func buildRunSummaries(from workouts: [HKWorkout]) {
        guard !workouts.isEmpty else {
            DispatchQueue.main.async {
                self.runsInPastWeek = []
                self.isLoadingRuns = false
            }
            return
        }

        let group = DispatchGroup()
        var summaries = Array<RunWorkoutSummary?>(repeating: nil, count: workouts.count)
        let lock = NSLock()

        for (index, workout) in workouts.enumerated() {
            group.enter()
            fetchHeartRateRange(for: workout) { minimumHeartRate, maximumHeartRate in
                let distanceMiles = workout.totalDistance?.doubleValue(for: .mile())
                let summary = RunWorkoutSummary(
                    id: workout.uuid,
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    duration: workout.duration,
                    distanceMiles: distanceMiles,
                    minimumHeartRate: minimumHeartRate,
                    maximumHeartRate: maximumHeartRate
                )

                lock.lock()
                summaries[index] = summary
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.runsInPastWeek = summaries.compactMap { $0 }
            self.isLoadingRuns = false
        }
    }

    private func fetchHeartRateRange(
        for workout: HKWorkout,
        completion: @escaping (Double?, Double?) -> Void
    ) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            completion(nil, nil)
            return
        }

        let workoutPredicate = HKQuery.predicateForObjects(from: workout)
        let datePredicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: []
        )
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [workoutPredicate, datePredicate])

        let query = HKStatisticsQuery(
            quantityType: heartRateType,
            quantitySamplePredicate: predicate,
            options: [.discreteMin, .discreteMax]
        ) { _, result, error in
            if let error = error {
                print("Heart rate query error: \(error.localizedDescription)")
                completion(nil, nil)
                return
            }

            let unit = HKUnit.count().unitDivided(by: .minute())
            let minimum = result?.minimumQuantity()?.doubleValue(for: unit)
            let maximum = result?.maximumQuantity()?.doubleValue(for: unit)
            completion(minimum, maximum)
        }

        healthStore.execute(query)
    }

    private func buildZone2PlusSummaries(from workouts: [HKWorkout], thresholdBPM: Int) {
        guard !workouts.isEmpty else {
            DispatchQueue.main.async {
                self.zone2PlusByDay = self.emptyZone2SummariesEndingToday()
                self.isLoadingZone2Plus = false
            }
            return
        }

        let group = DispatchGroup()
        var secondsByDay = initialSecondsByDayEndingToday()
        let lock = NSLock()

        for workout in workouts {
            group.enter()
            fetchZone2PlusSeconds(for: workout, thresholdBPM: thresholdBPM) { dailySeconds in
                lock.lock()
                for (day, seconds) in dailySeconds {
                    secondsByDay[day, default: 0] += seconds
                }
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.zone2PlusByDay = self.zone2Summaries(from: secondsByDay)
            self.isLoadingZone2Plus = false
        }
    }

    private func fetchZone2PlusSeconds(
        for workout: HKWorkout,
        thresholdBPM: Int,
        completion: @escaping ([Date: TimeInterval]) -> Void
    ) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            completion([:])
            return
        }

        let workoutPredicate = HKQuery.predicateForObjects(from: workout)
        let datePredicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: []
        )
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [workoutPredicate, datePredicate])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { [weak self] _, samples, error in
            guard let self else { return }

            if let error = error {
                print("Zone 2+ heart rate query error: \(error.localizedDescription)")
                completion([:])
                return
            }

            let heartRateSamples = (samples as? [HKQuantitySample]) ?? []
            let seconds = self.zone2PlusSecondsByDay(
                from: heartRateSamples,
                workoutEndDate: workout.endDate,
                thresholdBPM: thresholdBPM
            )
            completion(seconds)
        }

        healthStore.execute(query)
    }

    private func zone2PlusSecondsByDay(
        from samples: [HKQuantitySample],
        workoutEndDate: Date,
        thresholdBPM: Int
    ) -> [Date: TimeInterval] {
        guard !samples.isEmpty else { return [:] }

        let unit = HKUnit.count().unitDivided(by: .minute())
        var secondsByDay: [Date: TimeInterval] = [:]

        for index in samples.indices {
            let sample = samples[index]
            let heartRate = sample.quantity.doubleValue(for: unit)
            guard heartRate >= Double(thresholdBPM) else { continue }

            let nextStart: Date
            if index < samples.index(before: samples.endIndex) {
                nextStart = samples[samples.index(after: index)].startDate
            } else {
                nextStart = workoutEndDate
            }

            let rawInterval = max(0, nextStart.timeIntervalSince(sample.startDate))
            let cappedInterval = min(rawInterval, 300)
            let day = calendar.startOfDay(for: sample.startDate)
            secondsByDay[day, default: 0] += cappedInterval
        }

        return secondsByDay
    }

    private func estimatedZone2LowerBoundBPM() -> Int {
        let defaultMaxHeartRate = 170
        let maxHeartRate: Int

        if let age = userAge() {
            maxHeartRate = 220 - age
        } else {
            maxHeartRate = defaultMaxHeartRate
        }

        return Int((Double(maxHeartRate) * 0.60).rounded())
    }

    private func userAge() -> Int? {
        do {
            let components = try healthStore.dateOfBirthComponents()
            guard let birthDate = calendar.date(from: components) else { return nil }
            return calendar.dateComponents([.year], from: birthDate, to: Date()).year
        } catch {
            return nil
        }
    }

    private func initialSecondsByDayEndingToday() -> [Date: TimeInterval] {
        var result: [Date: TimeInterval] = [:]
        let today = calendar.startOfDay(for: Date())
        for offset in stride(from: 6, through: 0, by: -1) {
            if let day = calendar.date(byAdding: .day, value: -offset, to: today) {
                result[day] = 0
            }
        }
        return result
    }

    private func emptyZone2SummariesEndingToday() -> [Zone2DaySummary] {
        zone2Summaries(from: initialSecondsByDayEndingToday())
    }

    private func zone2Summaries(from secondsByDay: [Date: TimeInterval]) -> [Zone2DaySummary] {
        secondsByDay
            .map { day, seconds in
                Zone2DaySummary(date: day, minutes: Int((seconds / 60).rounded()))
            }
            .sorted { $0.date < $1.date }
    }
}
