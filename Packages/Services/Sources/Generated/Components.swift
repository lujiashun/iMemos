// Minimal stubs for generated OpenAPI types so local builds succeed
import Foundation

public enum Components {
    public enum Schemas {
        public struct Memo {
            public var content: String?
            public var pinned: Bool?
            public var state: State?
            public var visibility: Visibility?
            public var attachments: [Attachment]?
            public var createTime: Date?
            public var updateTime: Date?
            public var name: String?
            public var id: Int?

            public init(content: String? = nil, pinned: Bool? = nil, state: State? = nil, visibility: Visibility? = nil, attachments: [Attachment]? = nil, createTime: Date? = nil, updateTime: Date? = nil, name: String? = nil, id: Int? = nil) {
                self.content = content
                self.pinned = pinned
                self.state = state
                self.visibility = visibility
                self.attachments = attachments
                self.createTime = createTime
                self.updateTime = updateTime
                self.name = name
                self.id = id
            }

            public enum State {
                case ARCHIVED
                case OTHER
            }
        }

        public struct Attachment {
            // Minimal stubs for generated OpenAPI types so local builds succeed
            import Foundation

            public enum Components {
                public enum Schemas {
                    public struct Memo {
                        public var content: String?
                        public var pinned: Bool?
                        public var state: State?
                        public var visibility: Visibility?
                        public var attachments: [Attachment]?
                        public var createTime: Date?
                        public var updateTime: Date?
                        public var name: String?
                        public var id: Int?

                        public init(content: String? = nil, pinned: Bool? = nil, state: State? = nil, visibility: Visibility? = nil, attachments: [Attachment]? = nil, createTime: Date? = nil, updateTime: Date? = nil, name: String? = nil, id: Int? = nil) {
                            self.content = content
                            self.pinned = pinned
                            self.state = state
                            self.visibility = visibility
                            self.attachments = attachments
                            self.createTime = createTime
                            self.updateTime = updateTime
                            self.name = name
                            self.id = id
                        }

                        public enum State {
                            case ARCHIVED
                            case OTHER
                        }
                    }

                    public struct Attachment {
                        public var externalLink: String?
                        public var name: String?
                        public var filename: String
                        public var size: Int?
                        public var _type: String?
                        public var createTime: Date?

                        public init(externalLink: String? = nil, name: String? = nil, filename: String = "", size: Int? = nil, _type: String? = nil, createTime: Date? = nil) {
                            self.externalLink = externalLink
                            self.name = name
                            self.filename = filename
                            self.size = size
                            self._type = _type
                            self.createTime = createTime
                        }
                    }

                    // V0 styles
                    public struct Resource {
                        public var uid: String?
                        public var name: String?
                        public var filename: String?
                        public var externalLink: String?
                        public var size: Int?
                        public var _type: String?
                        public var createdTs: Int?
                        public var updatedTs: Int?
                        public var id: Int

                        public init(uid: String? = nil, name: String? = nil, filename: String? = nil, externalLink: String? = nil, size: Int? = nil, _type: String? = nil, createdTs: Int? = nil, updatedTs: Int? = nil, id: Int = 0) {
                            self.uid = uid
                            self.name = name
                            self.filename = filename
                            self.externalLink = externalLink
                            self.size = size
                            self._type = _type
                            self.createdTs = createdTs
                            self.updatedTs = updatedTs
                            self.id = id
                        }
                    }

                    public struct User {}
                    public struct InstanceProfile {}
                    public struct SystemStatus {}

                    public enum Visibility {
                        case PUBLIC
                        case PROTECTED
                        case PRIVATE
                    }
                }
            }
