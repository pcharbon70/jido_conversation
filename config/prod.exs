import Config

config :jido_conversation, Jido.Conversation.EventSystem,
  partition_count: 8,
  runtime_partitions: 8
