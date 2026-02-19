import Config

config :jido_conversation, JidoConversation.EventSystem,
  partition_count: 2,
  runtime_partitions: 2
