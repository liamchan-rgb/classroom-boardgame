import Foundation
import ClassroomGameCore

/// A saved class (班级): who the students are, so a new map can set up the whole party in one pick.
/// Only the new-trip choices are kept (name, look, job, team); nothing of a trip's progress.
public struct ClassRoster:Codable,Equatable,Identifiable {
    public struct Student:Codable,Equatable {
        public var name:String
        public var appearance:PlayerAppearance?
        /// One of MeadowPartyConfiguration.classIDs.
        public var classID:String
        /// 0 = 红队, 1 = 蓝队, 2 = 绿队.
        public var team:Int
        public init(name:String,appearance:PlayerAppearance?=nil,classID:String,team:Int=0) {
            self.name=name;self.appearance=appearance;self.classID=classID;self.team=team
        }
    }
    public static let maximumStudents=6
    public var name:String
    public var students:[Student]
    public var id:String {name}
    /// How many teams the class plays in (the highest team any student is in).
    public var teamCount:Int {min(3,max(1,(students.map(\.team).max() ?? 0)+1))}
    public init(name:String,students:[Student]) {self.name=name;self.students=students}

    /// Trims the name, keeps 1–6 students, and falls back to valid jobs and teams.
    public func validated()throws->ClassRoster {
        let trimmed=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty else{throw ClassRosterError.emptyName}
        guard !students.isEmpty else{throw ClassRosterError.noStudents}
        guard students.count<=Self.maximumStudents else{throw ClassRosterError.tooManyStudents}
        let ids=MeadowPartyConfiguration.classIDs
        return ClassRoster(name:String(trimmed.prefix(40)),students:students.map{s in
            // A look this version cannot draw is dropped (the student gets a default look) rather than failing the class.
            Student(name:String(s.name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(24)),appearance:s.appearance.flatMap{(try? $0.validate()) == nil ? nil:$0},
                    classID:ids.contains(s.classID) ? s.classID:ids[1],team:min(2,max(0,s.team)))
        })
    }
}

public enum ClassRosterError:LocalizedError,Equatable {
    case emptyName,noStudents,tooManyStudents
    public var errorDescription:String? {
        switch self {
        case .emptyName:"请给班级起个名字。"
        case .noStudents:"班级里至少要有一名学生。"
        case .tooManyStudents:"一个班级最多\(ClassRoster.maximumStudents)名学生。"
        }
    }
}

/// All saved classes in one small JSON file, sorted by name. Saving a class with an existing name replaces it.
public struct ClassRosterStore {
    public let url:URL
    public init(url:URL) {self.url=url}
    public func all()throws->[ClassRoster] {
        guard FileManager.default.fileExists(atPath:url.path) else{return []}
        return try JSONDecoder().decode([ClassRoster].self,from:Data(contentsOf:url))
    }
    @discardableResult public func save(_ roster:ClassRoster)throws->ClassRoster {
        let value=try roster.validated()
        var list=try all().filter{$0.name != value.name}
        list.append(value);list.sort{$0.name.localizedStandardCompare($1.name) == .orderedAscending}
        try write(list);return value
    }
    public func delete(_ name:String)throws {try write(try all().filter{$0.name != name})}
    private func write(_ list:[ClassRoster])throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(list).write(to:url,options:.atomic)
    }
}
