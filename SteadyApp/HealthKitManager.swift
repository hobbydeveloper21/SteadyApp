//
//  HealthKitManager.swift
//  SteadyApp
//
//  Created by ASHOK KUPPUSAMY on 6/1/26.
//

import Foundation
import HealthKit
import Combine

final class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()

    @Published var isAuthorized = false
    @Published var todaySteps: Double = 0
    @Published var todayActiveEnergy: Double = 0

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

        readTypes.insert(HKObjectType.workoutType())

        return readTypes
    }

    private func fetchTodaySum(
        for quantityType: HKQuantityType,
        unit: HKUnit,
        completion: @escaping (Double) -> Void
    ) {
        let calendar = Calendar.current
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
}
