import Foundation
import SwiftData

/// The data Bow 1.0 saves. A later release that changes a model adds `BowSchemaV2` with its own
/// copies of the changed models, and a stage to `BowMigrationPlan`, so 1.0 budgets open safely.
enum BowSchemaV1: VersionedSchema {
  static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

  static var models: [any PersistentModel.Type] {
    [
      BudgetProfile.self,
      BudgetAccount.self,
      BudgetGroup.self,
      BudgetEnvelope.self,
      BudgetTransaction.self,
      BudgetAllocation.self,
      BudgetPayee.self,
      BudgetSchedule.self,
      BudgetScheduleOccurrence.self,
      SimpleFINConnection.self,
      SimpleFINAccountLink.self,
      SimpleFINImportRecord.self
    ]
  }
}

enum BowMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] { [BowSchemaV1.self] }
  static var stages: [MigrationStage] { [] }
}
