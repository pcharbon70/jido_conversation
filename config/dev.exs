import Config

config :jido_conversation, Jido.Conversation.EventSystem,
  partition_count: 2,
  runtime_partitions: 2
