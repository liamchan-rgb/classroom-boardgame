import Foundation
import MeadowWorldSupport

public struct MeadowPartyJourneyReport:Codable,Equatable {
    public let configuration:MeadowPartyConfiguration
    public let journey:MeadowJourneyAuditReport
    public init(configuration:MeadowPartyConfiguration,journey:MeadowJourneyAuditReport){self.configuration=configuration;self.journey=journey}
}
